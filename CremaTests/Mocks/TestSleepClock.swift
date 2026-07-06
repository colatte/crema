import Foundation
@testable import Crema

/// Test clock: never really sleeps. Each `sleep(for:)` parks until the test
/// calls `advance()`; cancelling the sleeping Task throws CancellationError,
/// mirroring the real clock.
final class TestSleepClock: SleepClock, @unchecked Sendable {
    private let lock = NSLock()
    private var sleepers: [(id: UUID, delay: Double, continuation: CheckedContinuation<Void, Error>)] = []
    private var sleepWaiters: [(delay: Double?, continuation: CheckedContinuation<Void, Never>)] = []
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
                let waiters: [CheckedContinuation<Void, Never>]
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
                waiters = sleepWaiters
                    .enumerated()
                    .filter { $0.element.delay == nil || $0.element.delay == seconds }
                    .map(\.element.continuation)
                sleepWaiters.removeAll { $0.delay == nil || $0.delay == seconds }
                lock.unlock()
                waiters.forEach { $0.resume() }
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
    func waitForSleep() async {
        await waitForSleep(delay: nil)
    }

    /// Suspends until a sleep requested with `delay` is parked (nil = any).
    func waitForSleep(delay: Double?) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            let satisfied = sleepers.contains { delay == nil || $0.delay == delay }
            if satisfied {
                lock.unlock()
                continuation.resume()
            } else {
                sleepWaiters.append((delay, continuation))
                lock.unlock()
            }
        }
    }
}
