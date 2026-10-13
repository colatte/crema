import Foundation
import Testing
@testable import Crema

/// The deadline leg every race in the app arms (`SingleResumeRace.armDeadline`):
/// the subprocess wait, the OSD suppressor's applies and reads, and the
/// neighbour's command channel.
struct SingleResumeRaceTests {

    /// The leg is cancelled when the operation won or the caller tears the race
    /// down. A cancelled sleep that still committed its value would be stashed and
    /// resolve the next `begin` with a deadline nobody reached.
    @Test func aCancelledDeadlineLegResolvesNothing() async {
        let clock = TestSleepClock()
        let race = SingleResumeRace<Int, Never>()
        let leg = race.armDeadline(seconds: 5, on: clock, committing: .success(-1))
        await clock.waitForSleep()

        leg.cancel()
        await leg.value
        race.finish(42)

        let value = await withCheckedContinuation { race.begin($0) }
        #expect(value == 42)
    }

    /// Commit before unwind: the timeout hook unwinds the abandoned operation,
    /// whose own late finish must lose the single resume to the deadline's value.
    @Test func aFiredDeadlineCommitsBeforeItsHookRuns() async {
        let clock = TestSleepClock()
        let race = SingleResumeRace<Int, Never>()
        let leg = race.armDeadline(seconds: 5, on: clock, committing: .success(-1)) {
            race.finish(99)
        }
        await clock.waitForSleep()

        clock.advance()
        await leg.value

        let value = await withCheckedContinuation { race.begin($0) }
        #expect(value == -1)
    }
}
