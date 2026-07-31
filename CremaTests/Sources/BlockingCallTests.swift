import Foundation
import Testing
@testable import Crema

/// The property that matters is not "the value comes back" — it is *where the
/// call blocks*. A blocking C actuator that runs on a cooperative-pool thread
/// takes that thread out of circulation, and the pool does not overcommit; once
/// every thread is held, nothing on Swift concurrency runs again, including the
/// deadline that exists to abandon those very calls.
///
/// These waits are `DispatchSemaphore` with a wall-clock timeout on purpose. The
/// whole subject is starvation of the cooperative pool, so a waiter that needs
/// that pool to resume could not report the failure it is looking for — it would
/// hang the suite instead of failing it. Bounded, and released in `defer`.
struct BlockingCallTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var count: Int { lock.withLock { value } }
        func increment() -> Int { lock.withLock { value += 1; return value } }
    }

    @Test func aBlockedCallDoesNotHoldACooperativeThread() {
        let cores = ProcessInfo.processInfo.activeProcessorCount
        let gate = DispatchSemaphore(value: 0)
        let allStarted = DispatchSemaphore(value: 0)
        let started = Counter()

        // One stuck actuator per core: enough to hold the entire pool if these
        // ran there. Each body parks until `gate` is signalled, like a coreaudiod
        // stall or an output dropping mid-write.
        for _ in 0..<cores {
            Task.detached {
                try? await blockingCall {
                    if started.increment() == cores { allStarted.signal() }
                    gate.wait()
                }
            }
        }
        defer { for _ in 0..<cores { gate.signal() } }

        #expect(
            allStarted.wait(timeout: .now() + boundedWaitSeconds) == .success,
            "\(cores) blocking calls should all be able to start at once; the cooperative pool is only \(cores) threads wide"
        )

        // The decisive assertion: unrelated concurrency still runs. Drop the GCD
        // hop from blockingCall and the writes above hold every pool thread, so
        // this task is never scheduled and the app's timers and streams die with
        // it — the failure this whole seam exists to prevent.
        let probe = DispatchSemaphore(value: 0)
        Task.detached { probe.signal() }
        #expect(
            probe.wait(timeout: .now() + boundedWaitSeconds) == .success,
            "a task should still be scheduled while \(cores) blocking calls are parked"
        )
    }

    @Test func theValueComesBack() async throws {
        #expect(try await blockingCall { 7 } == 7)
    }

    @Test func theBodysErrorPropagatesUnchanged() async {
        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await blockingCall { throw Boom() }
        }
    }
}
