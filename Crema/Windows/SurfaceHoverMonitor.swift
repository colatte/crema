import AppKit

/// System edge: watches the real cursor and drives the surface's hover
/// against stable screen-space regions (`SurfaceHoverModel`), never the window
/// frame the panel animates. That decoupling is the fix — the loop came from the
/// old `.onHover`, whose tracking area rode the resizing panel and fired spurious
/// enter/exit events as the edge swept under a still cursor.
///
/// Thin by design: the decision is the pure, unit-tested model; this only samples
/// `NSEvent.mouseLocation` and forwards transitions. Real NSEvent monitors are a
/// border — smoke-tested on hardware.
///
/// UNVERIFIED hypothesis (hover round, kept deliberately unimplemented): while
/// the panel is interactive (ignoresMouseEvents == false) and the app is an
/// inactive accessory, macOS may throttle mouseMoved delivery to the global
/// monitor. Confirm with counters on hardware before adding any safety
/// re-sample — no speculative timer here.
@MainActor
final class SurfaceHoverMonitor {
    /// Plain moves plus the three mouse-ups — the ups are the re-sync point
    /// after a drag. `.mouseMoved` alone went blind the moment a button was
    /// down, deferring a drag-exit unboundedly; the release now samples the
    /// resting point (docs/DECISIONS.md: hover-follows-the-eye). Drags are
    /// deliberately NOT sampled: a live drag that started on the surface's own
    /// control keeps overshooting the edge (the HUD slider clamps while the
    /// cursor travels past), and releasing the hover hold mid-gesture would
    /// tuck the control out from under the finger — the same rule the panel's
    /// mouse-routing monitor documents.
    static let sampleEventMask: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp,
    ]
    private var model: SurfaceHoverModel
    private let report: (Bool) -> Void
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isInside = false
    private var isActive = false

    init(regions: SurfaceHoverRegions, report: @escaping (Bool) -> Void) {
        model = SurfaceHoverModel(regions: regions)
        self.report = report
    }

    /// Armed/disarmed by per-display policy (see PresentationPanel). Arming
    /// samples immediately: a stationary cursor already inside the region must
    /// register without waiting for movement, or the linger tucks the surface
    /// out from under it. Disarming reports a pending exit: the Coordinator
    /// mirrors the pointer from these reports, and a silent reset would leave
    /// that mirror stale (its guards then act on a pointer that isn't there).
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            install()
            sample()
        } else {
            teardown()
            if isInside {
                isInside = false
                report(false)
            }
        }
    }

    func stop() {
        setActive(false)
    }

    /// What detection is currently keyed on. Read-only, and it exists because the
    /// panel's retarget calls were invisible to every test: the region MATH is
    /// well pinned, but a mutation dropping the calls that push it left the suite
    /// green while the previous state's silhouette stayed live as an invisible
    /// sticky band (docs/DECISIONS.md: hover-follows-the-eye).
    var currentRegions: SurfaceHoverRegions { model.regions }

    /// How many retargets were REQUESTED, counted before the no-change guard.
    /// The count rather than the value, because the value cannot witness this:
    /// the apply-time retarget errs tight (rule frame ∩ last rendered), so two
    /// different states can legitimately land on the same rect and a dropped
    /// retarget would be indistinguishable from a redundant one.
    private(set) var retargetRequests = 0

    /// Retargets detection onto the surface as it is DRAWN — every layout pass,
    /// including mid-morph, because that is what "hover follows the eye" means:
    /// the region is the pixels the user is looking at, not the ones they will be
    /// looking at when the spring settles. The panel measures the animated frame
    /// (`.onGeometryChange` under the geometry animation) and pushes from
    /// `surfaceSizeChanged`, so reports arrive continuously and every skin sends
    /// them.
    ///
    /// The hysteresis band earns its keep on the way back rather than on the way
    /// out: with the region travelling along, an opening spring's overshoot is
    /// already inside it, and what would sting is the retreat — the frame
    /// shrinking under a cursor that had legitimately engaged. The exit margins
    /// keep that engagement instead of dropping it for a frame and re-taking it,
    /// which is the flicker this whole seam exists to avoid. Sizing is pinned by
    /// `stickyBandsAbsorbTheOpenSpringOvershoot`: the same numeric relation, held
    /// for this reason.
    ///
    /// Re-samples so a region that tightened under a stationary cursor (reactive
    /// appearance) corrects without waiting for a move; `sample` reports only on a
    /// real transition, so an unchanged answer stays quiet.
    /// (docs/DECISIONS.md: hover-follows-the-eye)
    func updateRegions(_ regions: SurfaceHoverRegions) {
        retargetRequests += 1
        guard regions != model.regions else { return }
        model = SurfaceHoverModel(regions: regions)
        if isActive {
            sample()
        }
    }

    private func install() {
        // BOTH are needed because they are mutually exclusive by design: the local
        // monitor sees only this app's own event stream, and the global one
        // explicitly does NOT observe the application it is installed in. So local
        // catches moves over our panel, global catches the cursor leaving it —
        // either alone is half a hover.
        //
        // `MainActor.assumeIsolated` below is an unconditional trap — a fatalError,
        // SIGTRAP, no throw and no degraded path — so it rests on a guarantee, and
        // the guarantee it needs is MAIN THREAD, which is exactly what the runtime
        // checks: outside Swift Concurrency (a runloop callout is outside it) the
        // main-executor check is `isMainExecutor() && isExecutingOnMainThread()` —
        // thread identity, never "the main dispatch queue".
        //
        // The only WRITTEN source is Apple's Cocoa Event Handling Guide, "Monitoring
        // Events": "The handlers are always called on the main thread", for both
        // monitors. That page sits in the Documentation Archive, last updated
        // 2016-09-13; the live NSEvent pages say nothing about threads, and as of the
        // macOS 26 SDK neither the AppKit header nor any @MainActor annotation on the
        // handler says it either. So the durable evidence is MEASURED, not cited:
        // posting from a background thread on macOS 26.5.2 / Swift 6.3.3, local AND
        // global monitor both arrived on the main thread. Re-running it is not
        // obvious — post a synthetic `.mouseMoved` on `.cghidEventTap` AT THE CURRENT
        // CURSOR POINT from a background thread with this process not frontmost, and
        // print `Thread.isMainThread` in both handlers; waving the mouse by hand
        // proves nothing, because the global monitor never observes its own app's
        // events. An archived page can be withdrawn, a measurement can be repeated.
        //
        // Guarding on `Thread.isMainThread` instead would test the same predicate the
        // runtime consults, so its else-branch is dead code no test reaches, and the
        // hop it would perform is the reordering these assumptions exist to avoid.
        // (docs/DECISIONS.md: assumed-isolation-is-measured)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: Self.sampleEventMask) { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.sampleEventMask) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    private func teardown() {
        localMonitor.map(NSEvent.removeMonitor)
        globalMonitor.map(NSEvent.removeMonitor)
        localMonitor = nil
        globalMonitor = nil
    }

    /// `NSEvent.mouseLocation` is the authoritative cursor point in global screen
    /// coordinates (bottom-left origin) — the same space as the regions, so no
    /// conversion. Only transitions are forwarded, to keep the Coordinator quiet.
    private func sample() {
        let inside = model.isInside(NSEvent.mouseLocation, wasInside: isInside)
        guard inside != isInside else { return }
        isInside = inside
        report(inside)
    }
}
