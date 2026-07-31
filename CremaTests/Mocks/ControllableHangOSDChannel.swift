import Foundation
@testable import Crema

/// A channel whose apply never returns on its own and never observes
/// cancellation — the genuinely uncancellable, blocked synchronous C actuator
/// write (a coreaudiod stall, a Bluetooth output dropping mid-write) that
/// MockOSDChannel.applyHangs (a cancellable Task.sleep) cannot model. The write
/// parks until the test calls release(), so a test can prove both that the
/// deadline abandons a truly stuck write and that a write landing long after
/// the deadline applies no zombie state. Access is lock-guarded because the
/// abandoned write task can land on any thread.
final class ControllableHangOSDChannel: OSDChannel, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Double? = 0.5
    private var _applied: [Double] = []
    private var _writeStartCount = 0
    private var _writeStartsSeen = 0
    private var parked: [CheckedContinuation<Void, Never>] = []

    var available = true
    var value: Double? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    /// Values that actually landed (only after a matching release()).
    var applied: [Double] { lock.withLock { _applied } }
    /// How many writes ever started — proves orphans do not pile up.
    var writeStartCount: Int { lock.withLock { _writeStartCount } }

    func isAvailable() -> Bool { available }

    func read() -> Double? { lock.withLock { _value } }

    func apply(_ newValue: Double) async throws {
        // Park with no cancellation handler and no timeout: a blocked C call
        // cannot see Task cancellation, so this never returns until release().
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            _writeStartCount += 1
            parked.append(continuation)
            lock.unlock()
        }
        // Reached only after release(): the actuator finally returns, landing
        // the write late — the honest residual the deadline accepts.
        lock.withLock {
            _applied.append(newValue)
            _value = newValue
        }
    }

    /// Completes the oldest parked write, as if the stuck actuator finally
    /// returned long after the deadline abandoned it.
    func release() {
        let continuation: CheckedContinuation<Void, Never>?
        lock.lock()
        continuation = parked.isEmpty ? nil : parked.removeFirst()
        lock.unlock()
        continuation?.resume()
    }

    /// Suspends until a write ARRIVES in apply() that no earlier wait has
    /// consumed, bounded by the wall clock. The continuation version was the
    /// last unbounded test-side await in the suite: on a starved runner the
    /// write it waited for had not been scheduled yet, and the whole run sat
    /// mute to the job timeout — the class round1-a1-a3 already deadlocked on.
    /// Consuming a COUNT rather than polling the parked list keeps the second
    /// call honest, because an abandoned first write stays parked forever by
    /// design and a wait that saw it would return before its own write began.
    /// On timeout it just returns; the assertion that follows fails loud.
    func waitForWriteStart() async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: boundedWaitDeadline)
        var spins = 0
        while clock.now < deadline {
            let arrived = lock.withLock {
                if _writeStartCount > _writeStartsSeen {
                    _writeStartsSeen = _writeStartCount
                    return true
                }
                return false
            }
            if arrived { return }
            spins += 1
            if spins < boundedWaitHotSpins {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }
}
