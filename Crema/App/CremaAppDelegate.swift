import AppKit

/// The one AppKit life-cycle callback SwiftUI has no counterpart for: holding the
/// quit while Crema hands a neighbour back what it took (NeighbourOSDHandoff).
/// `willTerminateNotification` comes after the last point where an answer can
/// still be awaited, and `ScenePhase` reports no quit at all.
///
/// Every orderly quit passes here — the menu's Quit, the updater's relaunch, a
/// logout — since all of them go through `terminate(_:)`, which asks
/// `applicationShouldTerminate(_:)` first (Apple, NSApplicationDelegate). A crash
/// or a force quit does not, which is why what is owed is persisted.
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
