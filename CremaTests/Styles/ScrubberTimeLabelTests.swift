import Testing
@testable import Crema

/// The scrubber's time labels. `Duration.seconds` traps on a value past Int64's
/// seconds, and a position reaches this label from whatever the player published.
struct ScrubberTimeLabelTests {

    @Test func aPositionNoTrackCanHaveStillPrints() {
        #expect(ScrubberRow.timeLabel(1e19, showsHours: true)
            == ScrubberRow.timeLabel(NowPlaying.maximumPosition, showsHours: true))
    }

    /// VoiceOver reads the bar as the times the row draws, not as a bare
    /// percentage of a span the listener never sees: the elapsed label always,
    /// and the length only where the row draws it (the Notch band does not).
    @Test func theAccessibilityValueIsTheDrawnTime() {
        let elapsed = ScrubberRow.timeLabel(65, showsHours: false)
        let length = ScrubberRow.timeLabel(200, showsHours: false)

        let both = ScrubberRow.accessibilityValue(shown: 65, duration: 200, showsDuration: true)
        #expect(both.contains(elapsed))
        #expect(both.contains(length))

        let elapsedOnly = ScrubberRow.accessibilityValue(shown: 65, duration: 200, showsDuration: false)
        #expect(elapsedOnly == elapsed)

        let stream = ScrubberRow.accessibilityValue(shown: 65, duration: nil, showsDuration: true)
        #expect(stream == elapsed)
    }
}
