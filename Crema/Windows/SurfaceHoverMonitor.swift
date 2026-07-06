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
@MainActor
final class SurfaceHoverMonitor {
    private let model: SurfaceHoverModel
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

    private func install() {
        // The local monitor catches moves over our own panel (events dispatched
        // to us); the global one catches moves elsewhere, so we still see the
        // cursor leave the surface. Both fire on the main run loop.
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            MainActor.assumeIsolated { self?.sample() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
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
