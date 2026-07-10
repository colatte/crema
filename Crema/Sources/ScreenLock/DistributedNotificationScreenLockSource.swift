import AppKit
import CoreGraphics
import Foundation
import os

/// Real screen-lock source. Combines fast edges with an authoritative poll:
/// `com.apple.screenIsLocked/Unlocked` (DistributedNotificationCenter) and the
/// session activate/resign notifications (NSWorkspace, fast-user-switch) give
/// latency, and every edge re-reads `CGSessionCopyCurrentDictionary` for the
/// truth. An edge alone never flips the state — reconciliation runs the poll
/// through `ScreenLockReconciler`, which is where all the logic (and its tests)
/// live. This class is the thin border: it wires notifications and reads the
/// session dictionary, nothing else.
///
/// The probe in docs/internal/LOCKSCREEN-INVESTIGATION.md validated exactly this
/// stack on hardware (edges fired, the poll flipped, onConsole stayed stable).
@MainActor
final class DistributedNotificationScreenLockSource: ScreenLockSource {
    // De-facto-stable private constants: the lock-edge notification names and
    // the session-dictionary keys. Not public API, but stable for years and
    // fine outside the Mac App Store; the authoritative poll (not the edge
    // names) is the source of truth, so a renamed edge only costs latency, not
    // correctness. kCGSSessionOnConsoleKey excludes fast-user-switch.
    private static let screenIsLockedName = "com.apple.screenIsLocked"
    private static let screenIsUnlockedName = "com.apple.screenIsUnlocked"
    private static let sessionScreenIsLockedKey = "CGSSessionScreenIsLocked"
    private static let sessionOnConsoleKey = "kCGSSessionOnConsoleKey"

    let updates: AsyncStream<Bool>
    private(set) var isSuppressionSafe: Bool

    private let continuation: AsyncStream<Bool>.Continuation
    private var reconciler: ScreenLockReconciler
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "ScreenLock"
    )

    init() {
        let session = Self.readSession()
        reconciler = ScreenLockReconciler(locked: session.locked, onConsole: session.onConsole)
        isSuppressionSafe = ScreenLockReconciler.isSuppressionSafe(locked: session.locked, onConsole: session.onConsole)

        var cont: AsyncStream<Bool>.Continuation!
        updates = AsyncStream { cont = $0 }
        continuation = cont

        installObservers()
    }

    deinit {
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        continuation.finish()
    }

    private func installObservers() {
        // Lock/unlock arrive on DistributedNotificationCenter; fast-user-switch
        // (off-console) arrives on the workspace center. Every edge funnels into
        // the same re-read — the notification is only a trigger.
        let distributed = DistributedNotificationCenter.default()
        for name in [Self.screenIsLockedName, Self.screenIsUnlockedName] {
            let observer = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue, so the MainActor is the current
                // executor — assume it rather than hop (avoids reordering edges).
                MainActor.assumeIsolated { self?.reconcileFromPoll() }
            }
            distributedObservers.append(observer)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconcileFromPoll() }
            }
            workspaceObservers.append(observer)
        }
    }

    private func reconcileFromPoll() {
        let session = Self.readSession()
        guard let safe = reconciler.reconcile(locked: session.locked, onConsole: session.onConsole) else { return }
        isSuppressionSafe = safe
        logger.info("suppression-safe → \(safe, privacy: .public) (locked=\(session.locked, privacy: .public) onConsole=\(session.onConsole, privacy: .public))")
        continuation.yield(safe)
    }

    /// The authoritative read. Absent dictionary or missing keys degrade to the
    /// safe/present interpretation (locked=false, onConsole=true) — a lock
    /// source that cannot read the session must not strand the user with
    /// suppression they can no longer see turned off; here it errs toward the
    /// normal desktop, where the poll on the next edge corrects it.
    private static func readSession() -> (locked: Bool, onConsole: Bool) {
        guard let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any] else {
            return (locked: false, onConsole: true)
        }
        let locked = (dictionary[sessionScreenIsLockedKey] as? Int ?? 0) != 0
        let onConsole = (dictionary[sessionOnConsoleKey] as? Int ?? 1) != 0
        return (locked: locked, onConsole: onConsole)
    }
}
