import Testing
@testable import Crema

/// The seek argument is the last place a number from the border becomes an
/// `Int`, and `Int(Double)` traps instead of failing. A live stream's sentinel
/// duration reached this conversion through the scrubber's own range and killed
/// the process on a normal drag — so the narrowing answers nil rather than
/// trapping, whatever upstream lets through.
struct AdapterSeekArgumentTests {
    private func micros(_ seconds: Double) -> Int? {
        MediaRemoteAdapterCommandChannel.microseconds(forSeek: seconds)
    }

    @Test func anOrdinaryPositionConvertsToMicroseconds() {
        #expect(micros(42.5) == 42_500_000)
        #expect(micros(0) == 0)
    }

    @Test func aNegativePositionIsFlooredAtZero() {
        #expect(micros(-3) == 0)
    }

    /// LLONG_MAX microseconds, the sentinel a live stream reports, carried back
    /// through seconds. Rounded up it is exactly 2^63 — one past `Int.max`.
    @Test func theLiveSentinelIsRejectedInsteadOfTrapping() {
        #expect(micros(9_223_372_036_854.775) == nil)
    }

    @Test func nonFiniteInputIsRejected() {
        #expect(micros(.nan) == nil)
        #expect(micros(.infinity) == nil)
    }
}
