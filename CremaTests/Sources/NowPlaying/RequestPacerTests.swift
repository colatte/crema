import Foundation
import Testing
@testable import Crema

/// The arithmetic behind "one request per second", with no clock and no actor.
///
/// Every value here is exact in binary floating point on purpose: a spacing of
/// 1 with a 0.25 offset leaves 0.75 with no rounding, so the assertions compare
/// numbers rather than tolerances.
struct RequestScheduleTests {

    @Test func theFirstRequestWaitsForNothing() {
        var schedule = RequestSchedule()
        #expect(schedule.reserve(at: 100, spacing: 1) == 0)
    }

    @Test func aRequestRightBehindAnotherWaitsOutTheRemainder() {
        var schedule = RequestSchedule()
        _ = schedule.reserve(at: 100, spacing: 1)
        #expect(schedule.reserve(at: 100.25, spacing: 1) == 0.75)
    }

    @Test func aRequestAfterTheGapHasPassedWaitsForNothing() {
        // The limit is a floor on the gap, not a toll on every request: a user
        // who changes track once an hour must never wait.
        var schedule = RequestSchedule()
        _ = schedule.reserve(at: 100, spacing: 1)
        #expect(schedule.reserve(at: 500, spacing: 1) == 0)
    }

    @Test func aBurstStacksInsteadOfCollapsing() {
        // The mutation this exists for: reserving `now + spacing` instead of
        // `slot + spacing` gives every caller in a burst the same one-second
        // wait, and the whole burst then leaves together — which is the request
        // storm the pacer was written to prevent. Three simultaneous callers owe
        // 0, 1 and 2 seconds.
        var schedule = RequestSchedule()
        let waits = (0..<3).map { _ in schedule.reserve(at: 100, spacing: 1) }
        #expect(waits == [0, 1, 2])
    }

    @Test func aTimebaseThatSlipsBackwardsNeverSchedulesInThePast() {
        // A negative wait would be handed to a sleep as a negative duration and,
        // worse, would read as "this slot is already yours" for a slot that is
        // not.
        var schedule = RequestSchedule()
        _ = schedule.reserve(at: 100, spacing: 1)
        #expect(schedule.reserve(at: 50, spacing: 1) >= 0)
    }
}

/// The actor around it: that the computed wait is actually waited, and that the
/// first caller pays nothing for the machinery.
struct RequestPacerTests {

    @Test @MainActor func theFirstTurnDoesNotSleepAtAll() async {
        let clock = TestSleepClock()
        let pacer = RequestPacer(spacing: 1, clock: clock, now: { 100 })
        await pacer.waitForTurn()
        // Not merely "returned quickly": a `sleep(for: 0)` on the real clock is
        // a suspension point, and a cover that arrives one hop later for no
        // reason is a hop this never needed to take.
        #expect(clock.delays.isEmpty)
    }

    @Test @MainActor func theSecondTurnActuallyWaits() async {
        let clock = TestSleepClock()
        let time = ManualNow()
        let pacer = RequestPacer(spacing: 1, clock: clock, now: { time.now.timeIntervalSince1970 })
        await pacer.waitForTurn()

        time.advance(by: 0.25)
        let second = Task { await pacer.waitForTurn() }
        await clock.waitForSleep()
        #expect(clock.delays == [0.75])
        clock.advance()
        await second.value
    }
}
