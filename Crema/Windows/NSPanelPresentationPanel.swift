import AppKit
import SwiftUI

/// AppKit border: the real panel. Deliberately thin — reconciliation, frame
/// math and style resolution live above (WindowManager) and are unit-tested;
/// this class only configures the NSPanel and applies what it is told.
///
/// For the real skins the window is fixed at the style's maximum frame and only
/// the SwiftUI content animates inside it (the model the mature notch apps
/// converged on). With the window never resizing there is no
/// window-frame-vs-render-commit ordering to coordinate — the whole class of
/// intermittent cropped-frame blinks dies by construction. The price is that
/// the fixed window overlaps the menu bar around the slit, paid for by click
/// routing: `ignoresMouseEvents` tracks the cursor against the current tight
/// rule frame (`SurfaceClickThrough`), so only the visible surface captures the
/// mouse and everything else falls through to what sits below.
@MainActor
final class NSPanelPresentationPanel: PresentationPanel {
    private let panel: NSPanel
    private let surface: PanelSurface
    /// Cursor-vs-stable-region hover detection; nil for styles without a
    /// distinct expanded surface.
    private let hoverMonitor: SurfaceHoverMonitor?
    /// Every skin animates its sized surface inside this window, which never
    /// resizes.
    private let fixedWindowFrame: CGRect
    /// Render context forwarded into the view: the layers this panel draws, and
    /// per-display now-playing suppression.
    private let displayPolicy: SurfaceDisplayPolicy
    /// Bridges the view's rendered-size reports (environment closure, baked at
    /// init before `self` is available) to the panel.
    private let sizeRelay = SurfaceSizeRelay()
    /// The click-interactive region, and it comes from the surface as DRAWN. Every
    /// skin reports its rendered size — the card because it hugs its width, the
    /// notch and classic because view-only shortens the surface — and measured, the
    /// hosting view reports during construction, so the reported path owns this
    /// rect before any apply can land. The rule frame below it is a net for a late
    /// report, not a mode the app runs in.
    private var interactiveRect: CGRect = .zero
    private var reportedSurfaceSize: CGSize?
    /// The last tight rule frame applied (empty ⇒ hidden, which always empties
    /// the interactive region — a fading, non-interactive ghost must not
    /// capture clicks).
    private var currentFrame: CGRect = .zero
    /// Click-invoke region (empty ⇒ none): with media playing and nothing
    /// visible, a click here opens the expanded appearance. It is exactly
    /// the compact rule frame — for the notch, the slit band — so the menus
    /// flanking it keep falling through untouched.
    private var invokeZone: CGRect = .zero
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    /// For reporting the click-invoke intent; the panel never reads state
    /// back (the WindowManager pushes everything it needs through apply).
    private weak var coordinator: Coordinator?

    /// Window facts for the tests that pin the fixed-window model. This class is
    /// opaque by design — reconciliation, frame math and style resolution live
    /// above it — but these two are invariants a one-line change breaks in
    /// silence, and without them no test can see either: mutations handing
    /// SwiftUI the power to size the window, and dropping the fixed frame
    /// entirely, both leave every other test green.
    /// (AGENTS.md "Never do".)
    var currentWindowFrame: CGRect { panel.frame }

    /// What this panel's hover detection is keyed on right now; nil for a style
    /// with no distinct expanded surface. Read-only, for the tests that pin the
    /// retarget — see `SurfaceHoverMonitor.currentRegions`.
    var currentHoverRegions: SurfaceHoverRegions? { hoverMonitor?.currentRegions }

    /// The layers this panel's view reads and the direction its HUD bar runs.
    /// Read-only, for the tests that pin which panel draws what: a panel built
    /// for the Card's HUD alone that read both layers would draw the card in a
    /// window sized for the HUD.
    var drawnLayers: PresentationLayers.Surface { displayPolicy.surface }
    var hudAxis: Axis { displayPolicy.hudAxis }

    /// The click-interactive rect. Read-only, and it exists to pin where this rect
    /// comes from: the rendered surface, from the first apply onward.
    var currentInteractiveRect: CGRect { interactiveRect }

    /// Retargets requested on this panel's monitor — see the property of the same
    /// purpose on SurfaceHoverMonitor.
    var hoverRetargetRequests: Int { hoverMonitor?.retargetRequests ?? 0 }

    /// Runs the window's own layout pass now, the pass in which a hosting view in
    /// charge of the window resizes it, so a test reads the frame after it rather
    /// than a run-loop turn before.
    func layOutWindowNow() {
        panel.layoutIfNeeded()
    }

    /// Whether the hosted SwiftUI content spans the whole fixed window: it sits
    /// in a plain content view, so nothing but its autoresizing keeps it there.
    var hostedContentFillsTheWindow: Bool {
        guard let content = panel.contentView, let hosted = content.subviews.first else { return false }
        return hosted.frame == content.bounds && content.bounds.size == panel.frame.size
    }

    /// `lowPower` carries no default on purpose: forgetting it at the factory then
    /// fails to compile instead of shipping panels whose waveform never stops
    /// (the lesson the `wire*` seams were extracted for).
    init(screen: ScreenDescription, surface: PanelSurface, coordinator: Coordinator, lowPower: LowPowerModeMirror?) {
        self.surface = surface
        self.coordinator = coordinator
        displayPolicy = SurfaceDisplayPolicy(surface: surface.layers, hudAxis: surface.hudAxis)
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Above the menu bar: the notch surface sits over the slit, which
        // overlaps the menu-bar region, so the panel must outrank it. A public
        // level (.mainMenu + 3, per the design reference) — no SkyLight/private
        // window APIs (WindowServer instability on macOS 26). Shared by every
        // style; harmless for the card/classic surfaces.
        //
        // No private window API here, whatever a level could buy: this panel
        // lives over the user's work, a public level does the job, and a
        // WindowServer wedge here breaks the app's core function for everyone
        // several times a day (docs/DECISIONS.md: the-lock-screen-is-a-space).
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Needed so the mouse routing's local monitor sees moves over the
        // panel; harmless otherwise (the panel stays non-activating).
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Inject the slit height (so the notch content lays out below the camera
        // cutout) and the rule-derived per-state sizes (so the view sizes its
        // surface within the fixed window). Both captured at creation, which is
        // why a geometry change rebuilds the panel (WindowManager). The Low Power
        // mirror rides along, but as a REFERENCE the composition root keeps
        // reporting into: an engage/disengage reaches a surface built long before
        // it, with no panel rebuild — the two captured values above cannot.
        let stateSizes = surface.stateSizes(on: screen.geometry)
        let root = surface.makeView(coordinator: coordinator, displayPolicy: displayPolicy)
            .environment(\.notchSlitInset, screen.geometry.safeTop)
            .environment(\.surfaceStateSizes, stateSizes)
            .environment(\.lowPowerMode, lowPower)
            .environment(\.surfaceSizeReporter, { [sizeRelay] size in sizeRelay.onChange?(size) })

        fixedWindowFrame = surface.windowFrame(on: screen.geometry)

        // Hover detection decoupled from the animating surface: sample
        // the real cursor against this style's stable regions and forward to the
        // Coordinator, naming the layers this panel draws. The notch debounces (top
        // edge); the others commit at once.
        if let regions = surface.hoverRegions(on: screen.geometry) {
            hoverMonitor = SurfaceHoverMonitor(regions: regions) { [weak coordinator, displayPolicy] inside, byMovement in
                // Panel-local first: the capsule knob is per-display, so only
                // the hovered surface reveals it; the Coordinator keeps the
                // global record its timers key on.
                displayPolicy.pointerInside = inside
                Self.forwardHover(inside, byMovement: byMovement, from: surface, to: coordinator)
            }
            // Activated per-display by apply(frame:hoverArmed:).
        } else {
            hoverMonitor = nil
        }

        // Wired before the content view exists: displaying the panel can drive
        // a synchronous layout pass, and the view's very first size report must
        // not land on a nil target.
        sizeRelay.onChange = { [weak self] size in
            self?.surfaceSizeChanged(size)
        }

        // SwiftUI must never drive the window frame, and a hosting view has two
        // ways to. The default sizingOptions (.standardBounds) install
        // min/intrinsic/max constraints; and as the window's content view it
        // updates the window's contentMinSize and contentMaxSize from its content
        // (Apple docs, NSHostingView.sizingOptions). Measured: with the constraints
        // off, the second still widens the upright HUD's window, narrower than the
        // card view's 180 pt floor, to that floor on the window's first layout, and
        // that HUD lands off the screen's right edge. So the hosting view sits inside a plain view
        // that fills the window; given a frame smaller than its content, it
        // centres the content (same doc), which is where every surface draws.
        let hostingView = NSHostingView(rootView: root)
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        let content = NSView()
        content.addSubview(hostingView)
        panel.contentView = content

        // The window exists once, front once, never resized or ordered out
        // again: an invisible (clear, click-through) window while the surface
        // is hidden costs nothing and removes every show/hide edge.
        panel.ignoresMouseEvents = true
        panel.setFrame(fixedWindowFrame, display: true)
        panel.orderFrontRegardless()
        installMouseRouting()
    }

    /// A hover on this panel, as the Coordinator takes it: naming the layers the
    /// panel draws, so a pointer on the Card's HUD alone holds the HUD and nothing
    /// else, and whether a mouse event caused the report, since a pointer the
    /// arming sample found holds no HUD. Static and internal so the tests reach the dispatch the monitor's
    /// callback runs — the monitor itself samples the real cursor.
    static func forwardHover(
        _ inside: Bool,
        byMovement: Bool,
        from surface: PanelSurface,
        to coordinator: Coordinator?
    ) {
        switch surface.hoverCommit {
        case .immediate: coordinator?.hover(inside, on: surface.layers, byMovement: byMovement)
        case .debounced: coordinator?.hoverIntent(inside, byMovement: byMovement)
        }
    }

    // swiftlint:disable function_parameter_count - one parameter per contract note, as PresentationPanel declares
    /// `frame` arrives in AppKit global screen coordinates (ScreenTranslation
    /// convention) and is the state's tight rule frame. It never touches the
    /// window: it bounds the click and hover regions, which follow the rendered
    /// surface (the view animates that surface on its own).
    func apply(
        frame: CGRect,
        hoverArmed: Bool,
        showsNowPlaying: Bool,
        showsHUD: Bool,
        showsControls: Bool,
        hudIndicatorStyle: HUDIndicatorStyle,
        invokeZone: CGRect?
    ) {
        // swiftlint:enable function_parameter_count
        self.invokeZone = invokeZone ?? .zero

        updateDisplayPolicy(
            showsNowPlaying: showsNowPlaying,
            showsHUD: showsHUD,
            showsControls: showsControls,
            hudIndicatorStyle: hudIndicatorStyle
        )

        currentFrame = frame
        // Hover retarget at apply time errs TIGHT: the current state's rule
        // frame ∩ the last rendered truth (the reported size still predates
        // this state change — while hidden it holds the FROZEN last-visible
        // silhouette). The genuine size report right after widens it to the
        // rendered truth; arming happens LAST in every path, so the arming
        // sample never judges a stale or oversized rect (docs/DECISIONS.md:
        // hover-follows-the-eye).
        if !frame.isEmpty {
            let rendered = reportedSurfaceSize.map { size in
                SurfaceClickThrough.surfaceRect(
                    size: size, window: fixedWindowFrame, anchor: surface.surfaceVerticalAnchor, topInset: surface.surfaceTopInset
                )
            }
            if let regions = SurfaceHoverRegions.forApply(
                ruleFrame: frame, lastRendered: rendered, margins: surface.hoverExitMargins
            ) {
                hoverMonitor?.updateRegions(regions)
            }
        }
        if reportedSurfaceSize != nil {
            // The view reports its rendered size: the region tracks the real
            // surface through morphs, no settle heuristics needed. At apply
            // time that report still PREDATES the state change (while hidden
            // it holds the frozen last-visible silhouette), so the click
            // region errs TIGHT exactly like the hover retarget above —
            // silhouette ∩ the state's rule frame — or an appearance out of
            // hidden would capture clicks on the old, larger silhouette over
            // the apps below until the first fresh report. Hover is NOT
            // pushed from here for the same staleness; only a fresh report
            // (surfaceSizeChanged) retargets both to the rendered truth.
            refreshReportedInteractiveRect(pushesHoverRegions: false, tightensToRuleFrame: true)
            hoverMonitor?.setActive(hoverArmed)
            return
        }
        // Reached only before the hosting view has reported a size, and measured:
        // it reports during construction, so no apply has ever landed here. No
        // settle belongs in this spot: a union-then-tighten settle over a
        // calibrated constant, for the shrink case, is machinery that cannot run,
        // with the constant asserted only against another constant. Anyone
        // calibrating click-during-close would turn a dial connected to nothing.
        //
        // The one line stays as a net: should a report ever be late, clicks land on
        // the rule frame rather than on nothing.
        interactiveRect = frame
        // Route immediately: a surface can appear under a stationary cursor
        // (reactive appearance, HUD keypress) and no mouse-move would fire to
        // unlock it.
        routeClicks(at: NSEvent.mouseLocation)
        hoverMonitor?.setActive(hoverArmed)
    }

    /// Internal, not private: the size relay is the production caller, and the
    /// tests drive this same seam to simulate reports deterministically — the
    /// real view's reports depend on a live layout pass no test controls.
    func surfaceSizeChanged(_ size: CGSize) {
        reportedSurfaceSize = size
        // From the first report on, the reported path owns the region outright.
        refreshReportedInteractiveRect()
    }

    /// Interactive region from the rendered surface: its size, top-center
    /// anchored (how the views draw it). Hidden always wins — the fading ghost
    /// still reports its size but must not capture clicks.
    private func refreshReportedInteractiveRect(pushesHoverRegions: Bool = true, tightensToRuleFrame: Bool = false) {
        guard let size = reportedSurfaceSize else { return }
        var visible: CGRect = currentFrame.isEmpty
            ? .zero
            : SurfaceClickThrough.surfaceRect(
                size: size, window: fixedWindowFrame, anchor: surface.surfaceVerticalAnchor, topInset: surface.surfaceTopInset
            )
        if tightensToRuleFrame {
            // Apply path only: the reported size predates the state, so the
            // click region may not exceed the state's tight rule frame — the
            // click-side twin of the hover retarget's errs-TIGHT rule.
            visible = Self.staleReportClickRect(rendered: visible, ruleFrame: currentFrame)
        }
        interactiveRect = visible
        // Hover follows the same rendered surface as clicks, on every style —
        // the two truths of one panel never diverge (docs/DECISIONS.md:
        // hover-follows-the-eye). The apply path passes false: its reported
        // size predates the state change, and apply already retargeted tight.
        // Hidden leaves the region as-is (hover is disarmed there, and the
        // next apply retargets before arming) and never adopts the empty
        // branch's window-tall report.
        if pushesHoverRegions, !visible.isEmpty {
            hoverMonitor?.updateRegions(.around(visible, margins: surface.hoverExitMargins))
        }
        routeClicks(at: NSEvent.mouseLocation)
    }

    /// The apply-time click rule, pure so the tests can pin it: a rendered
    /// silhouette that predates the state is trusted only where the state's
    /// tight rule frame agrees. Disjoint rects normalize to .zero (never
    /// CGRect.null, whose infinite origin would poison later comparisons); an
    /// empty rule frame (hidden) yields .zero, preserving the ghost-never-
    /// captures-clicks rule.
    nonisolated static func staleReportClickRect(rendered: CGRect, ruleFrame: CGRect) -> CGRect {
        let tight = rendered.intersection(ruleFrame)
        return tight.isEmpty ? .zero : tight
    }

    /// Render context into the view's policy box. Each flag is written only when
    /// it changes — belt-and-braces: an equal write through the generated setter
    /// is measured to fire nothing (`Coordinator.publishTrackNames` states where),
    /// but no Apple document promises it, and the guard keeps the intent at the
    /// call site for the cost of a comparison.
    private func updateDisplayPolicy(
        showsNowPlaying: Bool,
        showsHUD: Bool,
        showsControls: Bool,
        hudIndicatorStyle: HUDIndicatorStyle
    ) {
        if displayPolicy.showsNowPlaying != showsNowPlaying {
            displayPolicy.showsNowPlaying = showsNowPlaying
        }
        if displayPolicy.showsHUD != showsHUD {
            displayPolicy.showsHUD = showsHUD
        }
        if displayPolicy.showsControls != showsControls {
            displayPolicy.showsControls = showsControls
        }
        if displayPolicy.hudIndicatorStyle != hudIndicatorStyle {
            displayPolicy.hudIndicatorStyle = hudIndicatorStyle
        }
    }

    func close() {
        localMouseMonitor.map(NSEvent.removeMonitor)
        globalMouseMonitor.map(NSEvent.removeMonitor)
        localMouseMonitor = nil
        globalMouseMonitor = nil
        hoverMonitor?.stop()
        panel.orderOut(nil)
        panel.close()
    }

    /// The local monitor sees events while the window is interactive (they
    /// reach our app); the global one sees them while it is click-through
    /// (they go to the app below). Together they track the cursor across both
    /// routing states — the same pairing SurfaceHoverMonitor uses. Mouse-ups
    /// are matched too: a drag emits no mouseMoved, so its release is the one
    /// re-synchronization point after the cursor crosses the boundary mid-drag.
    private func installMouseRouting() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        // Both handlers assume the MainActor instead of hopping: NSEvent monitor
        // handlers are delivered on the main thread. It is an unconditional trap if
        // that ever stops being true, and Apple states it only in an archived guide —
        // the citation, its archive status and the measurement that outranks it are
        // written out once, at SurfaceHoverMonitor.install()
        // (docs/DECISIONS.md: assumed-isolation-is-measured), so there is one place
        // to re-verify instead of two copies to drift apart.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated {
                // Click-invoke: the mouse-up of a click the panel captured
                // inside the (empty) invoke zone. Filtered to this panel's
                // window — the local monitor sees the whole app's events.
                if event.type == .leftMouseUp, event.window === self?.panel {
                    self?.reportInvokeClick(at: NSEvent.mouseLocation)
                }
                self?.routeClicks(at: NSEvent.mouseLocation)
            }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeClicks(at: NSEvent.mouseLocation) }
        }
    }

    private func reportInvokeClick(at point: CGPoint) {
        guard SurfaceClickThrough.isInteractive(point, surface: invokeZone) else { return }
        coordinator?.invoke()
    }

    private func routeClicks(at point: CGPoint) {
        // The invoke zone captures the mouse exactly like a visible surface
        // does — that is what keeps a click from falling through to whatever
        // sits below while also letting everything outside both rects through.
        // Right/other buttons inside the zone are captured but not acted on:
        // the zone is the notch's dead slit, where they have nothing to hit
        // anyway (ignoresMouseEvents cannot be scoped per button).
        let interactive = SurfaceClickThrough.isInteractive(point, surface: interactiveRect)
            || SurfaceClickThrough.isInteractive(point, surface: invokeZone)
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }
}

/// The environment closure is baked into the root view during init, before
/// `self` can be captured; this box gets its target right after.
@MainActor
private final class SurfaceSizeRelay {
    var onChange: ((CGSize) -> Void)?
}
