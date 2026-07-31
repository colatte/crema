import Foundation

/// Owns the lock-aware engagement policy for the native-OSD suppressor.
///
/// The bug (proven on hardware — docs/LOCKSCREEN-INVESTIGATION.md): the
/// session event tap keeps receiving media keys while the screen is locked, so
/// with suppression on the app consumes the keys, suppresses the native OSD,
/// applies the writes itself, and cannot draw its own HUD over the lock shield —
/// the user gets zero feedback. The fix: while locked (or off-console),
/// suppression is *suspended* — keys flow back to the system, the native OSD
/// returns. On return, suppression re-engages if and only if the user
/// preference is on.
///
/// Invariant this type guarantees: the lock/unlock path never touches the user
/// preference. A user with suppression off sees zero change anywhere; a user
/// with it on keeps it on through any number of lock cycles.
///
/// No failure path writes the preference at all anymore: a failed apply used to
/// flip the persisted opt-in off through `onAutoDisengage`, the only non-user
/// write in the codebase. That write is gone — the suppressor now suspends the
/// failing *domain* in place (keys fall back to the native OSD, a probe
/// re-engages on recovery) and the pref stays the user's intent. This controller
/// therefore has nothing to guard against on the failure side; the lock invariant
/// is all that remains. (docs/DECISIONS.md: pref-sacred / per-domain-suspension)
///
/// Second responsibility: the unlock/return-to-console edge is also where the
/// media-key tap is physically recovered. After a lock/display-sleep/unlock the
/// tap can go ENABLED-but-deaf (valid, enabled, zero events — a server-side
/// unregistration no local check can see; docs/DECISIONS.md:
/// J7-estado-do-outro-lado), so on the safe edge the controller fires
/// `onUnlocked` *before* re-engaging, letting the
/// owner reinstall the tap ahead of the consumer being set. The stream is already
/// this type's single consumer, which is why the hook is born here.
@MainActor
final class SuppressionLockController {
    private let suppressor: (any NativeOSDSuppressor)?
    private let lockSource: any ScreenLockSource
    private let preferences: Preferences

    /// Fired on the unlock / return-to-console edge (safe false→true), BEFORE
    /// re-engagement, so the owner can physically recover the media-key tap
    /// ahead of the consumer being set — pinned order: unlock → reinstall →
    /// re-engage. Fires on the edge, not the level (a redundant safe=true with
    /// no lock in between does not re-fire), and independent of the preference:
    /// the tap's ENABLED-but-deaf failure kills plain observation too, so a
    /// pref-off user still needs the reinstall (docs/DECISIONS.md:
    /// J7-estado-do-outro-lado). Nil unless the owner wires a recovery.
    var onUnlocked: (@MainActor () -> Void)?

    private var isSafe: Bool
    private var consumeTask: Task<Void, Never>?

    init(
        suppressor: (any NativeOSDSuppressor)?,
        lockSource: any ScreenLockSource,
        preferences: Preferences
    ) {
        self.suppressor = suppressor
        self.lockSource = lockSource
        self.preferences = preferences
        self.isSafe = lockSource.isSuppressionSafe
    }

    /// Engages to the correct initial state — respecting a launched-while-locked
    /// start, which must not engage — and starts consuming lock transitions.
    func start() {
        applyEngagement()
        // lockSource captured by value so the for-await never retains self —
        // a strong ref parked on the stream would keep the controller alive
        // for the stream's whole life. The binding below lasts one iteration.
        consumeTask = Task { [weak self, lockSource] in
            for await safe in lockSource.updates {
                guard let self else { return }
                // The unlock / return-to-console edge (not the level): recover
                // the tap before re-engaging so the fresh port adopts the
                // consumer applyEngagement is about to set.
                let becameSafe = safe && !self.isSafe
                self.isSafe = safe
                if becameSafe { self.onUnlocked?() }
                self.applyEngagement()
            }
        }
    }

    /// The Settings-toggle path. Persist the wish always; engage only if the
    /// context is currently safe — toggling on while locked defers engagement to
    /// unlock, and toggling off engages nothing (and disengages if on).
    func setPreferredSuppression(_ enabled: Bool) {
        preferences.suppressesNativeOSD = enabled
        applyEngagement()
    }

    func stop() {
        consumeTask?.cancel()
        consumeTask = nil
    }

    /// The single decision point: suppress only when safe AND opted in. Reading
    /// the pref here (not caching it) keeps the two inputs — lock state and
    /// preference — always reconciled, whichever changed last.
    private func applyEngagement() {
        suppressor?.setEngaged(isSafe && preferences.suppressesNativeOSD)
    }
}
