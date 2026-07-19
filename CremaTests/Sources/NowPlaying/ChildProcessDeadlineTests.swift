import Foundation
import Testing
@testable import Crema

/// The pure subprocess-deadline race (audit A6): a fast operation returns its
/// value untouched, a hung one is abandoned at the deadline (and the "kill"
/// runs), and the single-resume guard never delivers twice. No real process —
/// the operation is a fake the test controls; the real Process wiring is the
/// thin border in runChildProcess.
struct ChildProcessDeadlineTests {

    @Test func aFastOperationReturnsItsValueAndNeverFiresTheDeadline() async {
        let clock = TestSleepClock()
        let killed = Flag()

        let result = await raceAgainstDeadline(
            { 42 },
            timeout: 10,
            clock: clock,
            timedOutValue: -1,
            onDeadline: { killed.value = true }
        )

        #expect(result == 42)
        #expect(!killed.value)   // the deadline was cancelled, not fired
    }

    @Test func aHungOperationIsAbandonedAtTheDeadlineAndKilled() async {
        let clock = TestSleepClock()
        let killed = Flag()
        let hang = HangingOperation(value: 42)

        let raceTask = Task {
            await raceAgainstDeadline(
                { await hang.run() },
                timeout: 10,
                clock: clock,
                timedOutValue: -1,
                // The "kill" both records itself and unwinds the operation, as a
                // real SIGTERM/SIGKILL makes the child's termination handler fire.
                onDeadline: { killed.value = true; hang.release() }
            )
        }

        await clock.waitForSleep(delay: 10)
        clock.advance(delay: 10)

        #expect(await raceTask.value == -1)   // the timed-out value, not 42
        #expect(killed.value)                 // terminate ran
        #expect(hang.wasReleased)             // and it unwound the operation
    }

    @Test func singleResumeDeliversTheFirstStashedResultOnly() async {
        // Both racers finish before begin installs the continuation: the first
        // result is stashed and delivered on begin; the loser no-ops.
        let race = SingleResumeRace<Int>()
        race.finish(1)
        race.finish(2)

        let value = await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            race.begin(continuation)
        }
        #expect(value == 1)
    }

    @Test func singleResumeIgnoresALateFinishAfterBegin() async {
        let race = SingleResumeRace<Int>()
        let waiter = Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                race.begin(continuation)
            }
        }
        // Let begin install, then race two finishes: exactly one wins, no crash.
        await Task.yield()
        race.finish(7)
        race.finish(9)

        #expect(await waiter.value == 7)
    }
}

/// A fake operation that parks until released — models a child process whose
/// termination handler only fires once it is killed. Lock-guarded because the
/// abandoned work task can land on any thread.
private final class HangingOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int, Never>?
    private var releasedValue: Int?
    private var _wasReleased = false
    private let value: Int

    init(value: Int) { self.value = value }

    var wasReleased: Bool { lock.withLock { _wasReleased } }

    func run() async -> Int {
        await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
            lock.lock()
            if let releasedValue {
                lock.unlock()
                continuation.resume(returning: releasedValue)
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        let parked: CheckedContinuation<Int, Never>?
        lock.lock()
        _wasReleased = true
        releasedValue = value
        parked = continuation
        continuation = nil
        lock.unlock()
        parked?.resume(returning: value)
    }
}
