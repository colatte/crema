import Foundation
import Testing
@testable import Crema

/// When the elapsed/duration labels stop fitting in `m:ss`.
///
/// The rule exists because `Duration`'s `.minuteSecond` pattern does not roll
/// over into hours — it keeps counting minutes. Measured on this machine before
/// the rule was written: 3600 s prints `60:00`, 7200 s prints `120:00`, and
/// 86 000 s prints `1.433:20` on a pt-BR Mac, grouping separator and all.
struct TimeLabelTests {

    @Test func songLengthsStayInMinutesAndSeconds() {
        // The overwhelming case, and the one the pattern is right for.
        #expect(!TimeLabel.reachesAnHour(0))
        #expect(!TimeLabel.reachesAnHour(169))
        #expect(!TimeLabel.reachesAnHour(3599))
    }

    @Test func anHourIsTheBoundaryAndItIsInclusive() {
        // Exactly 3600 must already be hours: it is the first value m:ss gets
        // wrong, printing 60:00 for something no listener reads as one hour.
        #expect(TimeLabel.reachesAnHour(TimeLabel.secondsInAnHour))
        #expect(TimeLabel.reachesAnHour(3601))
    }

    @Test func theLongContentTheBorderActuallyAdmitsIsCovered() {
        // The adapter drops LLONG_MAX but passes anything under 24 h, so
        // audiobooks, DJ sets and long streams arrive here in ordinary use.
        #expect(TimeLabel.reachesAnHour(7200))
        #expect(TimeLabel.reachesAnHour(86_000))
    }

    /// The formatted output, in a fixed locale, because the bug was visible in
    /// the STRING rather than in the predicate — and because pt-BR is where the
    /// grouping separator turned a time into a number.
    @Test func theHourPatternPrintsAnHourInsteadOfSixtyMinutes() {
        var brazilian = Duration.TimeFormatStyle(pattern: .hourMinuteSecond)
        brazilian.locale = Locale(identifier: "pt_BR")
        #expect(Duration.seconds(3600).formatted(brazilian) == "1:00:00")
        #expect(Duration.seconds(86_000).formatted(brazilian) == "23:53:20")

        // And the pattern the code used to use unconditionally, kept here as the
        // record of what it printed for the same inputs.
        var minutesOnly = Duration.TimeFormatStyle(pattern: .minuteSecond)
        minutesOnly.locale = Locale(identifier: "pt_BR")
        #expect(Duration.seconds(3600).formatted(minutesOnly) == "60:00")
    }
}
