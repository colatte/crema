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
/// Settle re-reads (docs/DECISIONS.md: settle-rereads / J6-latch-do-edge): the
/// unlock notification can be delivered a hair before
/// `CGSessionCopyCurrentDictionary` reflects the change, so the
/// single unlock edge can re-read a still-locked session. The reconciler
/// deduplicates that stale reading (the return-to-safe never emits) and, on a
/// plain lock/unlock, there is no second edge to correct it — the state latches
/// at the stale reading, the `SuppressionLockController` never re-engages, and
/// the media-key tap keeps observing (Crema HUD) while never swallowing (native
/// OSD back for good), across every key, until the next clean lock cycle or a
/// relaunch. The tap has a health-check poll for exactly this class of "we only
/// re-checked on an event that lied"; this source has its own equivalent. The
/// slow periodic tail (`settleTailInterval`) runs from construction — like the
/// tap poll, which health-checks from init — so the re-verification exists even
/// in the [launch, first edge) window: if the session's very first lock
/// notification is dropped (DistributedNotificationCenter is best-effort, with no
/// redundancy for a plain lock), the tail still catches the flip instead of
/// latching safe over a lock shield with no edge to correct it. `handleEdge`
/// reconciles the edge immediately, then restarts that same tail behind a short
/// finite backoff of extra authoritative re-reads for the sub-second common skew.
/// This is exact parity with the tap poll now — both re-verify from init; the
/// backoff alone was probabilistic, the unbounded tail makes the closure
/// deterministic for a skew that outlasts it, a future latch of this class, or a
/// dropped first notification. Each re-read feeds the same reconciler, so a
/// redundant one is silent (dedup) and the first to see the settled truth emits
/// the transition the edge missed. This never touches the reinstall path, the
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

    /// The slow periodic re-read interval. The tail runs from construction and
    /// again after each edge's finite backoff (a newer start restarts it; deinit
    /// ends it), so the re-verification never has a gap — not even the [launch,
    /// first edge) window. This turns the stale-edge latch from
    /// probabilistic — a skew that lands inside the backoff window, or an edge
    /// that never arrives because the first notification was dropped — into
    /// deterministic: it eventually converges regardless, exact parity with the
    /// media-key tap's health-check poll, which likewise re-verifies from init.
    /// Slow on purpose — the common skew is caught sub-second, so the tail only
    /// guards the rare residual latch or the pre-first-edge window; steady state
    /// is one silent deduped read per interval.
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

        // Arm the slow tail from construction, not just from the first edge: the
        // media-key tap health-checks from init, and this source must match, or a
        // dropped first lock notification would strand suppression safe over the
        // lock shield until some future edge (docs/DECISIONS.md: settle-rereads).
        // The first edge cleanly replaces this launch tail with its full
        // backoff-then-tail chain.
        startSettleReReads(withBackoff: false)

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
        startSettleReReads(withBackoff: true)
    }

    /// Starts the settle re-read chain: optionally a fast finite backoff, then a
    /// slow unbounded tail. Called two ways — from construction with no backoff
    /// (the launch tail, parity with the tap poll running from init: it covers the
    /// [launch, first edge) window), and from each edge with the backoff in front
    /// (the sub-second common skew). At most one chain runs at a time — a fresh
    /// start cancels the previous — so the first edge cleanly replaces the launch
    /// tail and a rapid lock→unlock never stacks chains. Cancellation (a newer
    /// start, or deinit) ends it cleanly. `clock` is captured by value so the
    /// sleep never retains `self`.
    private func startSettleReReads(withBackoff: Bool) {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self, clock = self.clock] in
            if withBackoff {
                for delay in Self.settleReReadBackoff {
                    do { try await clock.sleep(for: delay) } catch { return }   // cancelled
                    guard let self, !Task.isCancelled else { return }
                    self.reconcileFromPoll(caughtBySettle: true)
                }
            }
            // The tail re-reads until the next start (or deinit) so a skew that
            // outlasts the backoff, or a dropped first notification before any
            // edge ever arrives, still converges instead of latching forever — the
            // same role the tap's health-check poll plays, and likewise from init.
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
            // missed transition — the stale-edge latch in the act. The field
            // discriminator: a late flip with no notification edge immediately
            // before it.
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
