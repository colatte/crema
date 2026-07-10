@testable import Crema

/// Records engage/disengage flips and lets a test fire the auto-disengage
/// report, standing in for MediaKeyInterceptionOSDSuppressor so the lock-wiring
/// logic is tested without the real tap or channels.
@MainActor
final class RecordingOSDSuppressor: NativeOSDSuppressor {
    private(set) var isEngaged = false
    /// Every accepted flip, in order — lets a test assert the exact engage
    /// sequence across a lock cycle (e.g. no spurious re-engage).
    private(set) var engageHistory: [Bool] = []
    var onAutoDisengage: (@MainActor () -> Void)?
    var onApplied: (@MainActor (MediaKey) -> Void)?

    func setEngaged(_ engaged: Bool) {
        // Mirror the real suppressor: a redundant flip is a no-op.
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        engageHistory.append(engaged)
    }

    /// Simulate a straggling apply failure invoking the degradation report —
    /// the path that (only when actively suppressing) flips the persisted pref.
    func fireAutoDisengage() {
        onAutoDisengage?()
    }
}
