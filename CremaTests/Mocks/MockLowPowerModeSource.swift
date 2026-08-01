@testable import Crema

/// Test double for the Low Power Mode source. `set(_:)` updates the synchronous
/// read and then emits, in that order — the real source re-reads before it yields,
/// so anything that reads back while consuming an emission sees the same value.
/// `@MainActor` like the protocol, so tests drive it directly.
///
/// No wall clock of any kind: every transition is the test's, which is why a
/// starved runner can only make an assertion slower, never wrong.
@MainActor
final class MockLowPowerModeSource: LowPowerModeSource {
    let updates: AsyncStream<Bool>
    private(set) var isLowPower: Bool

    private let continuation: AsyncStream<Bool>.Continuation

    init(lowPower: Bool = false) {
        isLowPower = lowPower
        var continuation: AsyncStream<Bool>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    /// The state a power-state edge would have re-read. Emitting an unchanged
    /// value is deliberate and matches the real source: the edge fires for every
    /// power-source change, so repeats are the ordinary case and the consumer's
    /// guarded write is what turns them into silence.
    func set(_ lowPower: Bool) {
        isLowPower = lowPower
        continuation.yield(lowPower)
    }
}
