import AppKit
import CoreGraphics
import Foundation
import os

/// Real screen-lock source. Combines fast edges with an authoritative poll:
/// `com.apple.screenIsLocked/Unlocked` (DistributedNotificationCenter) and the
/// session activate/resign notifications (NSWorkspace, fast-user-switch) give
/// latency, and every edge re-reads `CGSessionCopyCurrentDictionary` for the
/// truth. An edge alone never flips the state — reconciliation runs the poll
/// through `ScreenLockReconciler`, and the dictionary itself is decoded by
/// `ScreenLockSessionTranslation`; between them they hold all the logic (and its
/// tests). This class is the thin border: it wires notifications and fetches the
/// session dictionary, nothing else.
///
/// The probe in docs/LOCKSCREEN-INVESTIGATION.md validated exactly this
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
    // The lock-edge notification names: undocumented — no SDK header declares
    // them — stable for years and fine outside the Mac App Store. The
    // authoritative re-read, not the edge names, is the source of truth, so a
    // renamed edge costs latency and not correctness.
    //
    // The session-dictionary keys are a different pedigree (one of them public,
    // one of them not) and live with the decoding that owns their shape, their
    // value types and what a missing key means: `ScreenLockSessionTranslation`.
    private static let screenIsLockedName = "com.apple.screenIsLocked"
    private static let screenIsUnlockedName = "com.apple.screenIsUnlocked"

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
    // nonisolated(unsafe): written only while `init` runs (installObservers)
    // and read only in `deinit`, after every other access has ended — the
    // lifecycle brackets rule out the concurrent access the attribute waives;
    // a nonisolated deinit can't see that bracket, and removeObserver itself
    // is thread-safe.
    private nonisolated(unsafe) var workspaceObservers: [NSObjectProtocol] = []
    /// The authoritative session read, injectable so a test can drive it
    /// (and the edges, via `handleEdge`) deterministically without the real
    /// CoreGraphics call.
    private let sessionReader: @MainActor () -> (locked: Bool, onConsole: Bool)
    /// Clock the settle re-reads sleep on (injectable for tests).
    private let clock: any SleepClock
    /// The in-flight settle re-read chain; at most one, restarted per edge.
    private var settleTask: Task<Void, Never>?

    /// A second reader's view of the raw `locked` bit. Nil when nobody asked —
    /// the suppression path never needs it, and a mirror nothing observes is a
    /// write per poll for no one (`LockScreenMirror`).
    private let lockMirror: LockScreenMirror?

    // Static because `readSession` is: the production reader runs inside `init`,
    // before `self` exists, so instance and border share this one logger.
    private static let logger = Logger.crema("ScreenLock")

    init(
        clock: any SleepClock = ContinuousSleepClock(),
        sessionReader: (@MainActor () -> (locked: Bool, onConsole: Bool))? = nil,
        lockMirror: LockScreenMirror? = nil
    ) {
        self.clock = clock
        self.lockMirror = lockMirror
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
        lockMirror?.report(locked: session.locked)

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
        // Self-registered now (the selector method is the only one that takes a
        // suspension behaviour), so the token list has nothing in it and the
        // removal has to name the observer instead. Leaving the old token loop
        // here would have quietly leaked both registrations.
        DistributedNotificationCenter.default().removeObserver(self)
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        continuation.finish()
    }

    /// The selector half of the registration above. Distributed notifications
    /// are delivered on the main thread for a main-thread registrant, which is
    /// the same assumption the workspace observers below make.
    @objc private func distributedEdgeArrived() {
        MainActor.assumeIsolated { handleEdge() }
    }

    private func installObservers() {
        // Lock/unlock arrive on DistributedNotificationCenter; fast-user-switch
        // (off-console) arrives on the workspace center. Every edge funnels into
        // the same handler — the notification is only a trigger.
        // Registered through the SELECTOR method, and only because it is the one
        // that takes a suspension behaviour.
        //
        // Every block-based cover is documented as defaulting to
        // `NSNotificationSuspensionBehaviorCoalesce`
        // (`NSDistributedNotificationCenter.h`: "All other registration methods
        // are covers of this one, with the default for suspensionBehavior =
        // NSNotificationSuspensionBehaviorCoalesce"), and coalesced delivery is
        // held while the centre is suspended — which AppKit does on its own
        // "when the application is not active". Crema is an LSUIElement
        // accessory: it is essentially NEVER active, and it is certainly not
        // active at the instant the screen locks. So the app was asking for the
        // one delivery mode that waits for a moment that may never come.
        //
        // `.deliverImmediately` is the documented opt-out — the server delivers
        // "irrespective of whether setSuspended:YES has been called", flushing
        // the queue as it goes. The settle re-reads and the periodic tail stay
        // exactly as they were: they exist because distnoted is best-effort even
        // when it IS delivering, and this changes nothing about that.
        let distributed = DistributedNotificationCenter.default()
        for name in [Self.screenIsLockedName, Self.screenIsUnlockedName] {
            distributed.addObserver(
                self,
                selector: #selector(distributedEdgeArrived),
                name: Notification.Name(name),
                object: nil,
                suspensionBehavior: .deliverImmediately
            )
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
        // Before the reconciler, deliberately. It deduplicates on `safe`, which
        // is `!locked && onConsole` — so locking or unlocking while off-console
        // moves `locked` and leaves `safe` false both times, and the guard below
        // returns early. A mirror written after it would never see that pair of
        // transitions. This one has its own guarded write, so reporting on every
        // poll costs nothing when nothing changed.
        lockMirror?.report(locked: session.locked)
        guard let safe = reconciler.reconcile(locked: session.locked, onConsole: session.onConsole) else { return }
        isSuppressionSafe = safe
        if caughtBySettle {
            // The edge read a stale session and a settle re-read caught the
            // missed transition — the stale-edge latch in the act. The field
            // discriminator: a late flip with no notification edge immediately
            // before it.
            Self.logger.notice("settle re-read caught a missed lock transition → safe=\(safe, privacy: .public)")
        }
        Self.logger.info("suppression-safe → \(safe, privacy: .public) (locked=\(session.locked, privacy: .public) onConsole=\(session.onConsole, privacy: .public))")
        continuation.yield(safe)
    }

    /// The authoritative read, and the whole of this type's system contact: fetch
    /// the session dictionary and hand it to the decoding that owns the keys, the
    /// value types and what an unreadable session means — NOT safe to suppress,
    /// never "normal desktop" (`ScreenLockSessionTranslation`, docs/DECISIONS.md:
    /// unreadable-session-is-unsafe). A missing dictionary is logged because it is
    /// believed unreachable inside an Aqua session (measured: always present), and
    /// the line is what would prove otherwise.
    private static func readSession() -> (locked: Bool, onConsole: Bool) {
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        if dictionary == nil {
            logger.error("session dictionary unreadable — decoding the session as unsafe to suppress")
        }
        return ScreenLockSessionTranslation.decode(dictionary)
    }
}
