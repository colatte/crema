import Foundation
@testable import Crema

/// Test clock: never really sleeps. Each `sleep(for:)` parks until the test
/// calls `advance()`; cancelling the sleeping Task throws CancellationError,
/// mirroring the real clock.
final class TestSleepClock: SleepClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [(id: UUID, delay: Double, continuation: CheckedContinuation<Void, Error>)] = []
    private var _delays: [Double] = []
    private var _cancelledCount = 0

    /// Every delay ever requested, in order.
    var delays: [Double] { lock.withLock { _delays } }
    /// How many sleeps were cancelled before completing (timer restarts).
    var cancelledCount: Int { lock.withLock { _cancelledCount } }
    var pendingSleeps: Int { lock.withLock { sleepers.count } }

    func sleep(for seconds: Double) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                // Cancellation can land between the entry check and the
                // handler's installation — the handler then fires before this
                // append and removes nothing, leaving an orphaned sleeper that
                // steals a later advance() from the live timer it replaced.
                if Task.isCancelled {
                    _cancelledCount += 1
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                _delays.append(seconds)
                sleepers.append((id, seconds, continuation))
                lock.unlock()
            }
        } onCancel: {
            let cancelled: CheckedContinuation<Void, Error>?
            lock.lock()
            if let index = sleepers.firstIndex(where: { $0.id == id }) {
                cancelled = sleepers.remove(at: index).continuation
                _cancelledCount += 1
            } else {
                cancelled = nil
            }
            lock.unlock()
            cancelled?.resume(throwing: CancellationError())
        }
    }

    /// Completes the oldest pending sleep, as if its deadline passed.
    func advance() {
        let resumed: CheckedContinuation<Void, Error>?
        lock.lock()
        resumed = sleepers.isEmpty ? nil : sleepers.removeFirst().continuation
        lock.unlock()
        resumed?.resume()
    }

    /// Completes the oldest pending sleep that was requested with `delay` —
    /// unambiguous when independent timers (linger + hover intent) are parked
    /// at once.
    func advance(delay: Double) {
        let resumed: CheckedContinuation<Void, Error>?
        lock.lock()
        if let index = sleepers.firstIndex(where: { $0.delay == delay }) {
            resumed = sleepers.remove(at: index).continuation
        } else {
            resumed = nil
        }
        lock.unlock()
        resumed?.resume()
    }

    /// Suspends until at least one sleep is parked.
    @MainActor
    func waitForSleep() async {
        await waitForSleep(delay: nil)
    }

    /// Suspends until a sleep requested with `delay` is parked (nil = any).
    /// Bounded yield-polling, not a parked continuation: a handshake that
    /// drifts out of alignment (waiting for a park that can never come) must
    /// surface as a loud downstream assertion failure, never wedge the suite
    /// forever — the deviceAbsent probe test deadlocked exactly that way.
    /// MainActor-isolated on purpose: the sleepers it awaits are parked by
    /// MainActor tasks (Coordinator timers, suppressor probes), so yielding
    /// must hand the MainActor over FIFO-fair — an off-actor yield loop burns
    /// its budget on the global executor before those tasks ever get a slot.
    @MainActor
    func waitForSleep(delay: Double?) async {
        for _ in 0..<20_000 {
            let satisfied = lock.withLock { sleepers.contains { delay == nil || $0.delay == delay } }
            if satisfied { return }
            await Task.yield()
        }
    }
}
