import AppKit
import QuartzCore
import SwiftUI

/// AppKit border: the real panel. Deliberately thin — reconciliation, frame
/// math and style resolution live above (WindowManager) and are unit-tested;
/// this class only configures the NSPanel and applies what it is told.
///
/// For the real skins the window is fixed at the style's maximum frame and only
/// the SwiftUI content animates inside it (design-reference §1.3, the
/// boring.notch model). With the window never resizing there is no
/// window-frame-vs-render-commit ordering to coordinate — the whole class of
/// intermittent cropped-frame blinks dies by construction. The price is that
/// the fixed window overlaps the menu bar around the slit, paid for by click
/// routing: `ignoresMouseEvents` tracks the cursor against the current tight
/// rule frame (`SurfaceClickThrough`), so only the visible surface captures the
/// mouse and everything else falls through to what sits below.
@MainActor
final class NSPanelPresentationPanel: PresentationPanel {
    private let panel: NSPanel
    private let style: Style
    /// Cursor-vs-stable-region hover detection; nil for styles without a
    /// distinct expanded surface.
    private let hoverMonitor: SurfaceHoverMonitor?
    /// Every current skin animates its sized surface inside the fixed window;
    /// nil is the defensive fallback for a future window-filling view (kept
    /// per-state window frames).
    private let fixedWindowFrame: CGRect?
    /// Per-display now-playing suppression, forwarded into the view.
    private let displayPolicy = SurfaceDisplayPolicy()
    /// Bridges the view's rendered-size reports (environment closure, baked at
    /// init before `self` is available) to the panel.
    private let sizeRelay = SurfaceSizeRelay()
    /// The click-interactive region. When the view reports its rendered size
    /// (the width-hugging card), the region follows it frame-by-frame; otherwise it
    /// falls back to the tight rule frame — and while a shrink settles it holds
    /// the union with the previous frame, so a click on still-visible pixels
    /// doesn't ghost through to the window below. (Growth captures the target
    /// immediately: eating a click a beat early is the safe direction.)
    private var interactiveRect: CGRect = .zero
    private var reportedSurfaceSize: CGSize?
    private var tightenTask: Task<Void, Never>?
    /// The last tight rule frame applied (empty ⇒ hidden, which always empties
    /// the interactive region — a fading, non-interactive ghost must not
    /// capture clicks).
    private var currentFrame: CGRect = .zero
    /// Click-invoke region (empty ⇒ none): with media playing and nothing
    /// visible, a click here surfaces the compact appearance. It is exactly
    /// the compact rule frame — for the notch, the slit band — so the menus
    /// flanking it keep falling through untouched.
    private var invokeZone: CGRect = .zero
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    /// For reporting the click-invoke intent; the panel never reads state
    /// back (the WindowManager pushes everything it needs through apply).
    private weak var coordinator: Coordinator?

    init(screen: ScreenDescription, style: Style, coordinator: Coordinator) {
        self.style = style
        self.coordinator = coordinator
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
        // why a geometry change rebuilds the panel (WindowManager).
        let stateSizes = style.stateSizes(on: screen.geometry)
        let root = style.makeView(coordinator: coordinator, displayPolicy: displayPolicy)
            .environment(\.notchSlitInset, screen.geometry.safeTop)
            .environment(\.surfaceStateSizes, stateSizes)
            .environment(\.surfaceSizeReporter, { [sizeRelay] size in sizeRelay.onChange?(size) })

        fixedWindowFrame = style.windowFrame(on: screen.geometry)

        // Hover detection decoupled from the animating surface: sample
        // the real cursor against this style's stable regions and forward to the
        // Coordinator. The notch debounces (top edge); the others commit at once.
        if let regions = style.hoverRegions(on: screen.geometry) {
            let commit = style.hoverCommit
            hoverMonitor = SurfaceHoverMonitor(regions: regions) { [weak coordinator] inside in
                switch commit {
                case .immediate: coordinator?.hover(inside)
                case .debounced: coordinator?.hoverIntent(inside)
                }
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

        let hostingView = NSHostingView(rootView: root)
        // SwiftUI must never drive the window frame: the default
        // sizingOptions (.standardBounds) install min/intrinsic/max constraints
        // that can resize the panel from the view's layout.
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        if let fixedWindowFrame {
            // The window exists once, front once, never resized or ordered out
            // again: an invisible (clear, click-through) window while the
            // surface is hidden costs nothing and removes every show/hide edge.
            panel.ignoresMouseEvents = true
            panel.setFrame(fixedWindowFrame, display: true)
            panel.orderFrontRegardless()
            installMouseRouting()
        }
    }

    // swiftlint:disable function_parameter_count
    /// `frame` arrives in AppKit global screen coordinates (ScreenTranslation
    /// convention) and is the state's tight rule frame. For the fixed-window
    /// skins it never touches the window: it becomes the click-interactive
    /// region (the view animates the matching surface on its own). A style
    /// without a fixed window falls back to direct per-state window frames.
    func apply(
        frame: CGRect,
        hoverArmed: Bool,
        showsNowPlaying: Bool,
        showsControls: Bool,
        hudIndicatorStyle: HUDIndicatorStyle,
        invokeZone: CGRect?
    ) {
        // swiftlint:enable function_parameter_count
        hoverMonitor?.setActive(hoverArmed)
        self.invokeZone = invokeZone ?? .zero

        guard fixedWindowFrame != nil else {
            applyDirectFrame(frame)
            return
        }

        if displayPolicy.showsNowPlaying != showsNowPlaying {
            displayPolicy.showsNowPlaying = showsNowPlaying
        }
        if displayPolicy.showsControls != showsControls {
            displayPolicy.showsControls = showsControls
        }
        if displayPolicy.hudIndicatorStyle != hudIndicatorStyle {
            displayPolicy.hudIndicatorStyle = hudIndicatorStyle
        }

        tightenTask?.cancel()
        tightenTask = nil
        let previous = currentFrame
        currentFrame = frame
        if reportedSurfaceSize != nil {
            // The view reports its rendered size: the region tracks the real
            // surface through morphs, no settle heuristics needed.
            refreshReportedInteractiveRect()
            return
        }
        if previous.isEmpty || frame.contains(previous) {
            interactiveRect = frame
        } else {
            // Shrinking (or hiding): hold the union while the close spring
            // settles, then tighten — the region follows the drawn surface out
            // instead of snapping to the target under still-visible pixels.
            interactiveRect = previous.union(frame)
            tightenTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(SurfaceAnimation.interactiveSettle))
                guard let self, !Task.isCancelled else { return }
                self.interactiveRect = frame
                self.routeClicks(at: NSEvent.mouseLocation)
            }
        }
        // Route immediately: a surface can appear under a stationary cursor
        // (reactive appearance, HUD keypress) and no mouse-move would fire to
        // unlock it.
        routeClicks(at: NSEvent.mouseLocation)
    }

    private func surfaceSizeChanged(_ size: CGSize) {
        reportedSurfaceSize = size
        // The reported path owns the region from here on: a pending fallback
        // tighten would clobber it with the stale rule frame.
        tightenTask?.cancel()
        tightenTask = nil
        refreshReportedInteractiveRect()
    }

    /// Interactive region from the rendered surface: its size, top-center
    /// anchored (how the views draw it). Hidden always wins — the fading ghost
    /// still reports its size but must not capture clicks.
    private func refreshReportedInteractiveRect() {
        guard let fixedWindowFrame, let size = reportedSurfaceSize else { return }
        let visible: CGRect = currentFrame.isEmpty
            ? .zero
            : SurfaceClickThrough.surfaceRect(size: size, window: fixedWindowFrame, anchor: style.surfaceVerticalAnchor)
        interactiveRect = visible
        // Hover follows the same rendered surface as clicks: the adaptive card
        // reports narrower than its rule ceiling, so a rule-derived region would
        // arm in the dead air beside the visible edge. Only the adaptive style
        // retargets; hidden leaves the region as-is (hover is disarmed there, so
        // a stale rect is never sampled) and never adopts the empty branch's
        // window-tall report.
        if style.hoverTracksRenderedSurface, !visible.isEmpty {
            hoverMonitor?.updateRegions(.around(visible))
        }
        routeClicks(at: NSEvent.mouseLocation)
    }

    /// Fallback for a window-filling view: per-state window frames. Mapping a
    /// previously ordered-out window waits for the render commit — it still
    /// holds the previous state's contents and would flash them for a frame.
    private func applyDirectFrame(_ frame: CGRect) {
        if frame.isEmpty {
            panel.setFrame(frame, display: false)
            panel.orderOut(nil)
        } else {
            panel.setFrame(frame, display: true)
            if panel.isVisible {
                panel.orderFrontRegardless()
            } else {
                CATransaction.setCompletionBlock { [weak self] in
                    guard let self, self.currentFrame == frame else { return }
                    self.panel.orderFrontRegardless()
                }
            }
        }
        currentFrame = frame
    }

    func close() {
        tightenTask?.cancel()
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
        // the zone is the notch's dead slit, where they had nothing to hit
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
final class SurfaceSizeRelay {
    var onChange: ((CGSize) -> Void)?
}
