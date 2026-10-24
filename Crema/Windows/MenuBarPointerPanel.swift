import AppKit
import SwiftUI

/// The arrow the welcome tour's last step points at the menu bar icon with: a
/// fixed, click-through panel standing under the icon, its only motion the
/// arrow's bob inside it.
///
/// Best effort by construction. The icon's frame comes from the app's own
/// window list (`StatusItemLocation`), and when it cannot be found — an icon
/// tucked away by macOS for room — the panel simply does not show: the step's
/// sentence already says where the app lives.
@MainActor
final class MenuBarPointerPanel {
    private let panel: NSPanel
    private let locate: @MainActor () -> CGRect?
    private let clock: any SleepClock

    init(
        locate: @escaping @MainActor () -> CGRect? = StatusItemLocation.frame,
        clock: any SleepClock = ContinuousSleepClock()
    ) {
        self.locate = locate
        self.clock = clock
        panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: Self.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // Over ordinary windows, under the menu bar it points at: the tour's own
        // window must not cover the arrow, and the arrow must not cover the icon.
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        // The hosting view inside a plain content view, never as it: a hosting
        // view set as the content view sizes the window to its content, and this
        // window's size is the rule's, not SwiftUI's.
        let content = NSView(frame: CGRect(origin: .zero, size: Self.size))
        let hosted = NSHostingView(rootView: MenuBarPointerArrow())
        hosted.frame = content.bounds
        hosted.autoresizingMask = [.width, .height]
        content.addSubview(hosted)
        panel.contentView = content
    }

    private var showing: Task<Void, Never>?

    /// Shows the arrow under the icon, or nothing when the icon cannot be found.
    /// Asked a few times before giving up: macOS builds the icon a moment after
    /// launch, and the tour can open on its last step sooner than that.
    func show() {
        showing?.cancel()
        showing = Task { [weak self, clock] in
            for _ in 0..<Self.attempts {
                guard let self, !Task.isCancelled else { return }
                if let item = locate() {
                    panel.setFrame(Self.frame(pointingAt: item), display: false)
                    panel.orderFrontRegardless()
                    return
                }
                // A cancel lands here as a throw; the guard above then ends it.
                try? await clock.sleep(for: Self.retryInterval)
            }
        }
    }

    func hide() {
        showing?.cancel()
        showing = nil
        panel.orderOut(nil)
    }

    /// About three seconds of asking, against the moment macOS takes to build
    /// the icon after launch.
    static let attempts = 12
    static let retryInterval = 0.25

    static let size = CGSize(width: 44, height: 56)

    /// Centered under `item`, its top a hair below the icon's bottom, on whole
    /// points so the arrow's edges never land between pixels. AppKit's global
    /// coordinates, like every frame rule here.
    static func frame(pointingAt item: CGRect) -> CGRect {
        CGRect(
            x: (item.midX - size.width / 2).rounded(),
            y: (item.minY - gap - size.height).rounded(),
            width: size.width,
            height: size.height
        )
    }

    private static let gap: CGFloat = 4
}

/// An up arrow on a dark disc, bobbing toward the icon. Under Reduce Motion it
/// stands still: the arrow points either way, and the motion carries nothing the
/// still picture does not (HIG, Motion).
private struct MenuBarPointerArrow: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised = false

    var body: some View {
        Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(.black.opacity(0.78), in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .offset(y: raised ? -6 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 6)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { raised = true }
            }
    }
}

/// Where this app's menu bar icon is: the one window of this process at the
/// status-bar level, which is the window macOS draws the icon in. Read from the
/// app's own window list by public properties alone — the window's class is
/// AppKit's private business — and in AppKit's global coordinates already.
enum StatusItemLocation {
    /// The icon's frame, or nil when there is none on a screen: the icon not
    /// built yet (macOS makes it a moment after launch), or tucked away for room.
    @MainActor
    static func frame() -> CGRect? {
        frame(among: NSApp.windows.map { (level: $0.level, frame: $0.frame) }, screens: NSScreen.screens.map(\.frame))
    }

    /// The rule, apart from AppKit: the first status-level window that sits on a
    /// screen. The app's own surfaces stand above that level and its windows
    /// below it, so nothing else of this process can answer.
    static func frame(among windows: [(level: NSWindow.Level, frame: CGRect)], screens: [CGRect]) -> CGRect? {
        windows.first { window in
            window.level == .statusBar && !window.frame.isEmpty && screens.contains { $0.intersects(window.frame) }
        }?.frame
    }
}
