import AppKit

/// The AppKit callback that can hold the quit while Crema hands a neighbour back
/// what it took (NeighbourOSDHandoff). `willTerminateNotification` is posted only
/// once this callback has answered `.terminateNow` (Apple,
/// NSApplication.willTerminateNotification), so the quit is decided by then, and
/// `ScenePhase` reports a scene's phase, with nothing that holds a quit.
///
/// Two routes reach it: `terminate(_:)`, which the menu's Quit calls and which
/// asks this delegate first (Apple, NSApplication.terminate(_:)); and the quit
/// Apple event, which a non-document app answers by asking it too (Apple, "How
/// Cocoa Applications Handle Apple Events") — the event Sparkle sends before it
/// installs an update (Sparkle 2.9.4, `SPUUserDriver.h`). A crash or a force quit
/// reaches neither, which is why what is owed is persisted.
@MainActor
final class CremaAppDelegate: NSObject, NSApplicationDelegate {
    /// What runs before the process may end, set once by the composition root.
    /// Static because SwiftUI instantiates this delegate (NSApplicationDelegateAdaptor)
    /// and the root is built inside a scene update, with no handle on the instance;
    /// nil quits at once.
    static var beforeQuitting: (@MainActor () async -> Void)?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let beforeQuitting = Self.beforeQuitting else { return .terminateNow }
        Task {
            await beforeQuitting()
            sender.reply(toApplicationShouldTerminate: true)
        }
        // AppKit runs the main run loop in NSModalPanelRunLoopMode until the reply
        // (Apple, NSApplication.TerminateReply.terminateLater).
        return .terminateLater
    }
}
