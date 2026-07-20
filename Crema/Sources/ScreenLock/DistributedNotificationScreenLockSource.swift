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
///
/// Settle re-reads (H-CONSUMER-NIL): the unlock notification can be delivered a
/// hair before `CGSessionCopyCurrentDictionary` reflects the change, so the
/// single unlock edge can re-read a still-locked session. The reconciler
/// deduplicates that stale reading (the return-to-safe never emits) and, on a
/// plain lock/unlock, there is no second edge to correct it — the state latches
/// at the stale reading, the `SuppressionLockController` never re-engages, and
/// the media-key tap keeps observing (Crema HUD) while never swallowing (native
/// OSD back for good), across every key, until the next clean lock cycle or a
/// relaunch. The tap has a health-check poll for exactly this class of "we only
/// re-checked on an event that lied"; this source now has its own equivalent.
/// `handleEdge` reconciles immediately, then schedules a short finite backoff of
/// extra authoritative re-reads for the sub-second common skew, and finally a
/// slow periodic tail (`settleTailInterval`) that keeps re-reading so a skew that
/// outlasts the backoff — or any future latch of this class — still converges
/// instead of latching unsafe forever, the same unbounded belt-and-suspenders the
/// tap poll provides (the finite backoff was probabilistic; the tail makes the
/// closure deterministic). Each re-read feeds the same reconciler, so a redundant
/// one is silent (dedup) and the first to see the settled truth emits the
/// transition the edge missed. This never touches the reinstall path, the
/// reconciler's dedup, or the engagement policy — the pref is still only ever
/// written by the user, and engagement still only follows a real safe=true.
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

    /// After each edge, re-read the authoritative session a few times on a short
    /// backoff to close the notification-vs-session-dict race (see the type
    /// doc). The skew is sub-second in practice; the first re-read at 150 ms is
    /// already generous margin, and 0.5/1.5 s add pathological headroom. This is
    /// the fast phase, restarted per edge; a slow unbounded tail
    /// (`settleTailInterval`) follows it so a skew that outlasts the backoff still
    /// converges. At most one chain runs at a time, and a steady state costs only
    /// silent (deduped) reads.
    private static let settleReReadBackoff: [Double] = [0.15, 0.5, 1.5]

    /// After the finite backoff, keep re-reading forever on this slow interval
    /// (until a newer edge restarts the chain, or deinit). This turns the
    /// H-CONSUMER-NIL closure from probabilistic — a skew that lands inside the
    /// backoff window — into deterministic: even a pathological skew that outlasts
    /// the backoff eventually converges, the same unbounded belt-and-suspenders
    /// the media-key tap's health-check poll provides. Slow on purpose — the
    /// common skew is already caught sub-second, so the tail only guards the rare
    /// residual latch; steady state is one silent deduped read per interval.
    private static let settleTailInterval: Double = 30

    let updates: AsyncStream<Bool>
    private(set) var isSuppressionSafe: Bool

    private let continuation: AsyncStream<Bool>.Continuation
    private var reconciler: ScreenLockReconciler
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// The authoritative session read, injectable so a test can drive it
    /// (and the edges, via `handleEdge`) deterministically without the real
    /// CoreGraphics call.
    private let sessionReader: @MainActor () -> (locked: Bool, onConsole: Bool)
    /// Clock the settle re-reads sleep on (injectable for tests).
    private let clock: any SleepClock
    /// The in-flight settle re-read chain; at most one, restarted per edge.
    private var settleTask: Task<Void, Never>?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "ScreenLock"
    )

    init(
        clock: any SleepClock = ContinuousSleepClock(),
        sessionReader: (@MainActor () -> (locked: Bool, onConsole: Bool))? = nil
    ) {
        self.clock = clock
        // A custom reader means a test drives the session read and injects edges
        // through `handleEdge` directly; the real DistributedNotificationCenter /
        // NSWorkspace observers would only add non-deterministic noise (a stray
        // lock during a run reading scripted values), so they are installed for
        // the production reader only.
        let usesRealReader = sessionReader == nil
        let reader = sessionReader ?? { Self.readSession() }
        self.sessionReader = reader

        let session = reader()
        reconciler = ScreenLockReconciler(locked: session.locked, onConsole: session.onConsole)
        isSuppressionSafe = ScreenLockReconciler.isSuppressionSafe(locked: session.locked, onConsole: session.onConsole)

        var cont: AsyncStream<Bool>.Continuation!
        updates = AsyncStream { cont = $0 }
        continuation = cont

        if usesRealReader { installObservers() }
    }

    deinit {
        settleTask?.cancel()
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
        // the same handler — the notification is only a trigger.
        let distributed = DistributedNotificationCenter.default()
        for name in [Self.screenIsLockedName, Self.screenIsUnlockedName] {
            let observer = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                // Delivered on the main queue, so the MainActor is the current
                // executor — assume it rather than hop (avoids reordering edges).
                MainActor.assumeIsolated { self?.handleEdge() }
            }
            distributedObservers.append(observer)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handleEdge() }
            }
            workspaceObservers.append(observer)
        }
    }

    /// The edge entry point — a delivered lock/unlock (or session
    /// activate/resign) notification funnels here. Internal so a test can inject
    /// an edge without a real notification: the injected `sessionReader` controls
    /// what the session reads at that instant. Reconciles the edge's reading
    /// immediately, then schedules the settle re-reads that catch a reading the
    /// edge took before the session dictionary settled.
    func handleEdge() {
        reconcileFromPoll()
        scheduleSettleReReads()
    }

    /// Restarts the settle re-read chain: a fast finite backoff, then a slow
    /// unbounded tail. At most one chain runs at a time, and a fresh edge gets a
    /// fresh full window (a rapid lock→unlock does not stack chains).
    /// Cancellation (a newer edge, or deinit) ends it cleanly. `clock` is
    /// captured by value so the sleep never retains `self`.
    private func scheduleSettleReReads() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self, clock = self.clock] in
            for delay in Self.settleReReadBackoff {
                do { try await clock.sleep(for: delay) } catch { return }   // cancelled
                guard let self, !Task.isCancelled else { return }
                self.reconcileFromPoll(caughtBySettle: true)
            }
            // The backoff alone closes the common skew only probabilistically;
            // this tail keeps re-reading until the next edge (or deinit) so a skew
            // that outlasts the backoff still converges instead of latching unsafe
            // forever — the same role the tap's health-check poll plays.
            while !Task.isCancelled {
                do { try await clock.sleep(for: Self.settleTailInterval) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.reconcileFromPoll(caughtBySettle: true)
            }
        }
    }

    private func reconcileFromPoll(caughtBySettle: Bool = false) {
        let session = sessionReader()
        guard let safe = reconciler.reconcile(locked: session.locked, onConsole: session.onConsole) else { return }
        isSuppressionSafe = safe
        if caughtBySettle {
            // The edge read a stale session and a settle re-read caught the
            // missed transition — the H-CONSUMER-NIL latch in the act. The
            // field discriminator: a late flip with no notification edge
            // immediately before it.
            logger.notice("settle re-read caught a missed lock transition → safe=\(safe, privacy: .public)")
        }
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
