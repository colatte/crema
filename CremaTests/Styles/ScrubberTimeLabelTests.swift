import Testing
@testable import Crema

/// The scrubber's time labels. `Duration.seconds` traps on a value past Int64's
/// seconds, and a position reaches this label from whatever the player published.
struct ScrubberTimeLabelTests {

    @Test func aPositionNoTrackCanHaveStillPrints() {
        #expect(ScrubberRow.timeLabel(1e19, showsHours: true)
            == ScrubberRow.timeLabel(NowPlaying.maximumPosition, showsHours: true))
    }
}
