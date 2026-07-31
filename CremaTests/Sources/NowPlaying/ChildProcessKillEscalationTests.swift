import Foundation
import Testing
@testable import Crema

/// The one part of the subprocess border that only a real process can witness:
/// the escalation from a polite terminate to SIGKILL.
///
/// `ChildProcessDeadlineTests` pins the pure race with a fake operation, which
/// is where the interesting logic lives — but the guarantee the decision is
/// named for ("the child is abandoned AND killed", docs/DECISIONS.md:
/// child-process-deadline, born of a hung child stalling the whole now-playing
/// chain) is a signal sequence, and a fake cannot ignore a signal. A mutation
/// deleting the SIGKILL left the entire suite green.
///
/// So this suite spawns a real child — deliberately, and narrowly: it is
/// `/bin/sh` with a trap and nothing of the app in it, it cannot outlive the
/// test (the teardown kills it either way), and it exercises exactly one thing.
/// This is the same narrow exception the wall-clock waits in TestSupport carry:
/// the rule is that production logic stays testable above the border, not that
/// the border may never be exercised at all.
struct ChildProcessKillEscalationTests {

    /// A child that catches SIGTERM and keeps running — the shape that hung the
    /// chain before the escalation existed. It echoes AFTER installing the trap:
    /// between exec and the trap there is a window where SIGTERM still kills it,
    /// and on a starved runner the test's terminate landed inside that window —
    /// the child died politely and the "SIGTERM alone did nothing" assertion
    /// failed. The echo is the proof the trap is armed; the test waits for it
    /// (bounded) before it lets the deadline fire.
    private func deafChild() -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", #"trap "" TERM; echo ready; sleep 30"#]
        return process
    }

    /// Off-main flag for the readiness echo — the readability handler runs on
    /// a dispatch queue, so the seam tests' MainActor Flag cannot carry it.
    private final class ReadyFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var isSet = false
        var value: Bool { lock.withLock { isSet } }
        func set() { lock.withLock { isSet = true } }
    }

    @Test func aChildThatIgnoresTerminationIsKilledAfterTheGrace() async {
        let process = deafChild()
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        let ready = ReadyFlag()
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            if !handle.availableData.isEmpty {
                ready.set()
                handle.readabilityHandler = nil
            }
        }
        let clock = TestSleepClock()

        let run = Task {
            await runChildProcess(
                process,
                timeout: 5,
                clock: clock,
                failureValue: "abandoned",
                interpret: { finished, _ in "exited(\(finished.terminationStatus))" }
            )
        }

        await clock.waitForSleep()          // the deadline is armed
        #expect(await eventuallyOffActor { ready.value })   // the trap is armed too
        clock.advance()                     // it fires: terminate, then the grace
        let result = await run.value
        #expect(result == "abandoned")      // the caller is freed immediately
        #expect(process.isRunning)          // …and SIGTERM alone did nothing

        await clock.waitForSleep()          // the kill grace is armed
        clock.advance()                     // it elapses

        #expect(await eventuallyOffActor { !process.isRunning })
    }

    @Test func aChildThatHonoursTerminationNeedsNoKill() async {
        // The polite path: terminate is enough, and the caller is freed by the
        // same deadline either way.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 30"]
        defer { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        let clock = TestSleepClock()

        let run = Task {
            await runChildProcess(
                process,
                timeout: 5,
                clock: clock,
                failureValue: "abandoned",
                interpret: { finished, _ in "exited(\(finished.terminationStatus))" }
            )
        }

        await clock.waitForSleep()
        clock.advance()
        #expect(await run.value == "abandoned")

        #expect(await eventuallyOffActor { !process.isRunning })
    }
}
