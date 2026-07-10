@testable import Crema

/// Test double for the screen-lock source. The test drives lock/unlock and
/// off-console transitions through `set(safe:)`, which updates the synchronous
/// read and emits — matching the real source's contract (the emitted value is
/// the reconciled authoritative state). `@MainActor` like the protocol, so the
/// tests drive it directly.
@MainActor
final class MockScreenLockSource: ScreenLockSource {
    let updates: AsyncStream<Bool>
    private(set) var isSuppressionSafe: Bool

    private let continuation: AsyncStream<Bool>.Continuation

    init(safe: Bool = true) {
        isSuppressionSafe = safe
        var continuation: AsyncStream<Bool>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// Locked/unlocked or off-/on-console, reduced to the one bit the source
    /// exposes: safe = unlocked AND on-console.
    func set(safe: Bool) {
        isSuppressionSafe = safe
        continuation.yield(safe)
    }
}
