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
/// written to end (`design-reference` §1.3). The empty region is transparent
/// and `ignoresMouseEvents` keeps it from swallowing anything.
@MainActor
final class LockScreenPanel {
    private let panel: NSPanel
    private let space: any RaisedSpace
    private let logger = Logger.crema("LockScreen")

    /// Nil when SkyLight could not be resolved — the caller degrades instead of
    /// showing a window that would sit uselessly behind the shield.
    init?(
        screen: NSScreen,
        coordinator: Coordinator,
        space: any RaisedSpace,
        lowPower: LowPowerModeMirror,
        artwork: LockArtworkResolver
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
        // space's own absolute level. High here so nothing of ours lands on top.
        panel.level = NSWindow.Level(rawValue: Int(Int32.max) - 2)

        let hosting = NSHostingView(rootView: AnyView(
            LockWidgetView(coordinator: coordinator, artwork: artwork)
                .environment(\.lowPowerMode, lowPower)
        ))
        // The default (.standardBounds) installs constraints that let SwiftUI
        // resize the window; this one is sized by the screen and nothing else.
        hosting.sizingOptions = []
        panel.contentView = hosting

        panel.setFrame(screen.frame, display: true)
        panel.orderFrontRegardless()
        space.adopt(panel)
    }

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

    func setFrame(_ frame: CGRect) {
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        // A resized window is a new window as far as the space is concerned on
        // some paths; re-adopting is free and convergent.
        space.adopt(panel)
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}
