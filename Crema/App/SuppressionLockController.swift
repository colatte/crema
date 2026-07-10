import Foundation

/// Owns the lock-aware engagement policy for the native-OSD suppressor.
///
/// The bug (proven on hardware — docs/internal/LOCKSCREEN-INVESTIGATION.md): the
/// session event tap keeps receiving media keys while the screen is locked, so
/// with suppression on the app consumes the keys, suppresses the native OSD,
/// applies the writes itself, and cannot draw its own HUD over the lock shield —
/// the user gets zero feedback. The fix: while locked (or off-console),
/// suppression is *suspended* — keys flow back to the system, the native OSD
/// returns. On return, suppression re-engages if and only if the user
/// preference is on.
///
/// Two invariants this type guarantees:
/// - The lock/unlock path never touches the user preference. A user with
///   suppression off sees zero change anywhere; a user with it on keeps it on
///   through any number of lock cycles.
/// - `onAutoDisengage` (a failed apply flipping the persisted pref off, so the
///   Settings toggle stops lying) is inert while suspended. A straggling apply
///   failure racing the lock edge must not silently persist the pref off. This
///   is belt-and-suspenders over the suppressor's generation counter, which
///   already no-ops applies enqueued before the lock-edge `setEngaged(false)`
///   (bumped generation → the applyVerified and autoDisengage guards fall
///   through); the guard here additionally covers the async gap between the
///   lock happening and this controller processing the edge.
@MainActor
final class SuppressionLockController {
    private let suppressor: (any NativeOSDSuppressor)?
    private let lockSource: any ScreenLockSource
    private let preferences: Preferences

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
        suppressor?.onAutoDisengage = { [weak self] in
            // Only a real apply failure while we are actively suppressing may
            // flip the persisted opt-in. Suspended-by-lock, we never apply, so
            // any failure that reaches here is a straggler — leave the pref be.
            // Read the source's synchronous state, not this controller's cache:
            // the source flips on the notification itself, one hop before our
            // stream task runs, so a straggler racing the lock edge is caught.
            guard let self, self.lockSource.isSuppressionSafe else { return }
            self.preferences.suppressesNativeOSD = false
        }
        applyEngagement()
        consumeTask = Task { [weak self] in
            guard let self else { return }
            for await safe in self.lockSource.updates {
                self.isSafe = safe
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
