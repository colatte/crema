@testable import Crema

/// Records engage/disengage flips, standing in for
/// MediaKeyInterceptionOSDSuppressor so the lock-wiring logic is tested without
/// the real tap or channels. Per-domain suspension is the suppressor's own
/// concern (covered by its unit tests); this double only needs the engage
/// surface the lock controller drives.
@MainActor
final class RecordingOSDSuppressor: NativeOSDSuppressor {
    private(set) var isEngaged = false
    /// Every accepted flip, in order — lets a test assert the exact engage
    /// sequence across a lock cycle (e.g. no spurious re-engage).
    private(set) var engageHistory: [Bool] = []
    var onApplied: (@MainActor (MediaKey) -> Void)?
    var onHandedBackToTheSystem: (@MainActor (MediaKey) -> Void)?

    private(set) var longSuspendedDomains: Set<OSDSuppressionDomain> = []
    var onSuspensionStateChange: (@MainActor () -> Void)?
    private(set) var retryCount = 0

    func setEngaged(_ engaged: Bool) {
        // Mirror the real suppressor: a redundant flip is a no-op.
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        engageHistory.append(engaged)
    }

    func retrySuspendedNow() { retryCount += 1 }
}
