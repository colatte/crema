import AppKit
import os
import SwiftUI

/// The window the lock-screen surface lives in: one screen-sized borderless
/// panel, raised out of the default space so the shield cannot cover it.
///
/// It is deliberately NOT a `PresentationPanel`. That protocol's `apply(...)`
/// already carries seven parameters behind a lint opt-out and four fakes
/// implement it, and every one of those parameters describes a surface with
/// frame states, hover regions and a click-through rule — none of which this
/// one has. An eighth dimension for a surface that is either up or down would
/// cost every existing implementer and buy nothing.
///
/// Screen-sized from the start, in both states. The card only occupies its
/// bottom strip, but expanding hands the cover the whole display, and a window
/// that resized between the two would be an AppKit frame change racing a
/// SwiftUI render — the exact family of flicker the fixed-window rule was
/// written to end (`design-reference` §1.3).
///
/// Being screen-sized is also this window's one real hazard, and the reason for
/// the mouse routing below. Transparency does NOT pass a click through — this
/// repo measured that for the desktop panels, which is why they carry the same
/// machinery — so a clear window this size captures every click on the display.
/// Over the lock shield those clicks belong to the password field, the avatar
/// and the Cancel/Switch-User buttons. The window is therefore born
/// click-through and only opens where the card is drawn.
@MainActor
final class LockScreenPanel {
    private let panel: NSPanel
    private let space: any RaisedSpace
    private let logger = Logger.crema("LockScreen")

    /// The card's rect in AppKit global screen coordinates, republished by the
    /// view whenever it moves. Empty means capture nothing, which is both the
    /// starting value and the resting state whenever no media is playing.
    private var interactiveRect: CGRect = .zero
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    /// Nil when SkyLight could not be resolved — the caller degrades instead of
    /// showing a window that would sit uselessly behind the shield.
    /// `makeContent` exists for one reason and it is worth the parameter: it is
    /// the only way to observe THE WIRE THE VIEW WAS HANDED.
    ///
    /// That wire broke for two commits and the symptom was silent — the card
    /// drew perfectly and answered no click, nothing logged, nothing crashed.
    /// The cause was a relay box held by a local `let` and captured `[weak]`, so
    /// it died the instant `init` returned. Two tests written against it passed,
    /// both because they called the panel's own copy of the closure instead of
    /// the one baked into the hosting view; from outside, those are
    /// indistinguishable. A seam that hands the closure to the caller is what
    /// makes the difference observable, and `AppCoreWiringSeamTests` is the
    /// precedent: pin the joins where a mis-wire compiles, runs, and produces a
    /// wrong-but-plausible app.
    init?(
        screen: NSScreen,
        coordinator: Coordinator,
        space: any RaisedSpace,
        lowPower: LowPowerModeMirror,
        artwork: LockArtworkResolver,
        makeContent: ((@escaping (CGRect) -> Void) -> NSView)? = nil
    ) {
        guard space.isAvailable else { return nil }
        self.space = space

        panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Public, and load-bearing: without it AppKit refuses to show the window
        // while no session is logged in, and the raised space alone does not
        // save you (`NSWindow.h`, since 10.5).
        panel.canBecomeVisibleWithoutLogin = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // Ordering within the raised space, which is a different axis from the
        // space's own absolute level. High here so nothing of ours lands on top
        // — but at the DOCUMENTED ceiling, not past it. `kCGMaximumWindowLevel`
        // is `INT32_MAX - kCGNumReservedWindowLevels` (CGWindowLevel.h), so the
        // top 16 values are Apple's; `Int32.max - 2`, which this used to be,
        // sits inside that band and above `kCGCursorWindowLevel` itself. Nothing
        // enforces the ceiling, which is exactly why it is worth respecting: the
        // window is alone in its own space, so it gains nothing from the extra
        // 14 and would only be claiming precedence over the system's own layers.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

        // Born capturing nothing. Every later value comes from the card's own
        // rendered rect, so the window can only open where something is drawn —
        // and if the routing below ever stops running, the lock screen keeps
        // every one of its clicks and the card simply is not clickable. The
        // failure is a feature that does not respond, never a login UI that
        // does not.
        panel.ignoresMouseEvents = true

        // Built before the content and handed to it verbatim — one closure, no
        // box in between. Creating it afterwards would also miss the first
        // report: the reporter fires from `onAppear` on the first layout pass,
        // which SwiftUI may run the moment the hosting view is installed, and
        // the rect does not change again.
        let report: (CGRect) -> Void = { [weak self] rect in self?.setInteractiveRect(rect) }

        if let makeContent {
            panel.contentView = makeContent(report)
        } else {
            let hosting = NSHostingView(rootView: AnyView(
                LockWidgetView(coordinator: coordinator, artwork: artwork, onInteractiveRect: report)
                    .environment(\.lowPowerMode, lowPower)
            ))
            // The default (.standardBounds) installs constraints that let
            // SwiftUI resize the window; this one is sized by the screen.
            hosting.sizingOptions = []
            panel.contentView = hosting
        }

        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        space.adopt(panel)

        installMouseRouting()
    }

    // MARK: - Mouse routing

    /// Called by the content view, through the closure it was handed at init,
    /// with the card's rect in the window's coordinate space.
    private func setInteractiveRect(_ cardInWindow: CGRect) {
        interactiveRect = LockWidgetClickThrough.screenRect(
            cardInWindow: cardInWindow, window: panel.frame
        )
        // Re-route on the spot instead of waiting for the next mouse event: the
        // card can shrink or leave under a stationary cursor (the media stops,
        // the card collapses) and no move is emitted for that, so the window
        // would stay open over pixels the card no longer covers.
        routeClicks(at: NSEvent.mouseLocation)
    }

    /// The local monitor sees events while the window is capturing; the global
    /// one sees them while it is click-through. Neither alone tracks the cursor
    /// across that boundary, which is why the desktop panels pair them too
    /// (`NSPanelPresentationPanel.installMouseRouting`). Mouse-ups are matched
    /// because a drag emits no `mouseMoved`, so its release is the one moment
    /// the routing can resynchronize after the cursor crossed mid-drag.
    ///
    /// That this works AT ALL over the lock shield is measured, not assumed, and
    /// it was worth measuring: Apple documents that a global monitor "would not
    /// be able to detect Command-Tab or a system alert", and the lock screen is
    /// loginwindow's UI. It does not generalize —
    /// `scripts/probes/lockscreen-mouse-routing.swift` counted 1092 global
    /// mouse-moved events while locked, with a window in exactly this
    /// configuration. The same run showed `NSEvent.mouseLocation` polling alive
    /// there too, which is the standing fallback if a macOS release ever takes
    /// delivery away: swap the mechanism here, and nothing else moves.
    private func installMouseRouting() {
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp]
        // Assuming the MainActor rather than hopping: NSEvent monitor handlers
        // are delivered on the main thread, and the citation plus the
        // measurement that outranks it are written out once, at
        // SurfaceHoverMonitor.install() (docs/DECISIONS.md:
        // assumed-isolation-is-measured).
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            MainActor.assumeIsolated { self?.routeClicks(at: NSEvent.mouseLocation) }
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            MainActor.assumeIsolated { self?.routeClicks(at: NSEvent.mouseLocation) }
        }
    }

    private func routeClicks(at point: CGPoint) {
        let interactive = SurfaceClickThrough.isInteractive(point, surface: interactiveRect)
        if panel.ignoresMouseEvents == interactive {
            panel.ignoresMouseEvents = !interactive
        }
    }

    /// Whether the window is currently taking clicks away from whatever is
    /// under it. Readable because it is the one fact about this window that can
    /// hurt somebody: on the lock screen, "captures" and "the password field
    /// does not respond" are the same sentence.
    var capturesMouse: Bool { !panel.ignoresMouseEvents }

    /// Called on every edge that can have reconfigured WindowServer state —
    /// display sleep and wake, system wake, screen-parameter changes.
    ///
    /// Unconditional and idempotent, which is the same shape the media-key tap
    /// already uses for the same reason (`docs/DECISIONS.md:
    /// preventive-reinstall`, `J7-estado-do-outro-lado`): whether a raised space
    /// survives a sleep is state living in the WindowServer, and this process
    /// cannot audit it — a local read would answer "fine" either way. Acting on
    /// the edge costs one cheap call; trusting a local read costs a surface that
    /// silently stopped appearing.
    func reassertSpace() {
        space.adopt(panel)
    }

    /// Re-applies the frame and ALWAYS re-adopts, even when the frame did not
    /// move. The early return this used to take made the topology edge a no-op
    /// in its most common shape — plugging a second display in leaves the main
    /// screen's frame untouched — so the one edge that most plausibly
    /// reconfigures the WindowServer was the one edge that re-asserted nothing,
    /// against three comments promising the opposite. The re-adopt is the whole
    /// point of the edge; the frame is the part that is conditional.
    func setFrame(_ frame: CGRect) {
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
            // The rect the view reported was measured against the old window
            // origin, so it names the wrong place on screen now. Empty until the
            // view republishes, which is the safe direction: capture nothing.
            interactiveRect = .zero
        }
        space.adopt(panel)
    }

    func close() {
        removeMouseRouting()
        panel.orderOut(nil)
        panel.close()
    }

    /// `close()` is the single teardown, and there is deliberately no `deinit`
    /// backstop. Every path that drops a panel closes it first — `reconcile()`
    /// on unlock and on the preference going off, and the presenter's own
    /// `deinit` — so a backstop would only add a `MainActor.assumeIsolated` in a
    /// nonisolated `deinit`, which traps if the last reference is ever released
    /// off the main thread. A crash is a worse failure than the leak it covers.
    private func removeMouseRouting() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }
}
