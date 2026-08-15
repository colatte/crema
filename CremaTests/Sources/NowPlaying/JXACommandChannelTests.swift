import Testing
@testable import Crema

/// The fallback chain's seek argument, where a number from the border is
/// interpolated into a JavaScript statement instead of narrowed to an `Int`. The
/// failure mode is the quieter of the two the family has: `max(0, .nan)` is 0, so
/// an unusable number used to become a silent seek to the START of the track —
/// the player obeys, the user watches the song jump back, and nothing anywhere
/// reports a failure. The adapter sibling (`AdapterSeekArgumentTests`) guards the
/// same value for the same reason; only the trap it avoids differs.
struct JXACommandChannelTests {
    private func position(_ seconds: Double) -> Double? {
        JXACommandChannel.playerPosition(forSeek: seconds)
    }

    @Test func anOrdinaryPositionPassesThrough() {
        #expect(position(42.5) == 42.5)
        #expect(position(0) == 0)
    }

    @Test func aNegativePositionIsFlooredAtZero() {
        // Players reject a negative position; the start of the track is what the
        // user was reaching for.
        #expect(position(-3) == 0)
    }

    @Test func nonFiniteInputIsRejectedInsteadOfFloored() {
        // Rejected rather than floored: nil reaches the caller as
        // `commandFailed` — the controls degrade, which is honest — while the
        // floor would seek to 0 and call it success.
        #expect(position(.nan) == nil)
        #expect(position(.infinity) == nil)
        #expect(position(-.infinity) == nil)
    }
}
