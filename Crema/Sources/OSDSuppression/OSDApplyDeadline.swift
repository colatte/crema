import Foundation

/// The deadline-race machinery MediaKeyInterceptionOSDSuppressor bounds its
/// applies and reads with, split out to keep that file focused (its private
/// collaborators live in OSDSuppressionDecider.swift).
///
/// An operation races a deadline so the deadline can always return — even
/// against a call that never completes and never observes cancellation (a
/// blocked synchronous C actuator or read). The deadline sleep always fires, so
/// the continuation is resumed exactly once whatever the operation does — and a
/// late orphan is pure, its result dropped by the single-resume guard. The one
/// hard rule: the operation must never run where a blocked call could starve the
/// deadline's own resumption.
///
/// - A write is an async operation on an *unstructured, detached* task. A
///   structured child (task group / `async let`) is joined at scope exit, which
///   a hung call would block forever, defeating the very deadline this enforces;
///   unstructured lets the timeout return while the call finishes orphaned on a
///   background thread, off the MainActor. On timeout it is cancelled (tidy-up
///   for a cancellable call, a no-op for a blocked one) and abandoned.
///   Precondition, and the whole reason `blockingCall` exists: the operation
///   must genuinely SUSPEND while it waits. An `async` signature is no proof of
///   that — an actuator whose body is a straight-line C call runs to completion
///   on the pool thread that picked it up, and then this detached task is the
///   pool-starving orphan the read rule below was written to prevent.
/// - A read is a blocking synchronous C call, so it runs on a GCD global queue,
///   never a detached task. The cooperative pool has a fixed width (one thread
///   per core) and never overcommits: a read that blocks forever would consume a
///   pool thread permanently, and the recovery probe re-emits that same read
///   every backoff cycle, so leaked orphans accumulate without bound and starve
///   the pool. The deadline sleep resumes on that same pool, so an exhausted
///   pool stops the deadline firing — a fresh apply on a healthy domain would
///   then hang forever with its keys still consumed. GCD's global queue spawns
///   threads when its own block, so an orphan parked there costs a thread out of
///   that queue's own ceiling instead of the app's concurrency — bounded, not
///   free. (docs/DECISIONS.md: read-deadline-pool-rule,
///   async-signature-is-not-a-suspension-point)

/// Thrown when the operation outlives its deadline. The caller maps it onto its
/// own suspension path.
enum DeadlineExceeded: Error {
    case timedOut
}

/// Races an async write against `seconds` on `clock`; rethrows the write's own
/// error unchanged and `DeadlineExceeded.timedOut` on timeout.
func raceWriteDeadline(
    seconds: Double,
    clock: any SleepClock,
    _ operation: @escaping @Sendable () async throws -> Void
) async throws {
    try await raceDeadline(seconds: seconds, clock: clock) {
        do {
            try await operation()
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}

/// Races a synchronous, blocking C read against `seconds` on `clock`, returning
/// its value; throws `DeadlineExceeded.timedOut` if the read stalls past the
/// deadline. The read runs on a GCD global queue (see the file header) so a
/// blocked call never occupies a cooperative-pool thread — the pool the deadline
/// itself resumes on. There is nothing to cancel: an orphan just completes here
/// and its result is dropped by the single-resume guard.
func raceReadDeadline<T: Sendable>(
    seconds: Double,
    clock: any SleepClock,
    _ read: @escaping @Sendable () -> T
) async throws -> T {
    let race = DeadlineRace<T>()
    DispatchQueue.global().async { race.finish(.success(read())) }
    return try await race.awaitDeadline(seconds: seconds, clock: clock)
}

private func raceDeadline<T: Sendable>(
    seconds: Double,
    clock: any SleepClock,
    _ produce: @escaping @Sendable () async -> Result<T, Error>
) async throws -> T {
    let race = DeadlineRace<T>()
    let operation = Task.detached { await race.finish(produce()) }
    return try await race.awaitDeadline(seconds: seconds, clock: clock) { operation.cancel() }
}

/// Single-resume guard for the operation/deadline race: `T == Void` for a write,
/// the read's value for a read. The abandoned operation can land on any thread,
/// so the guard is lock-based rather than actor-bound; whichever racer finishes
/// first resumes the continuation and the rest no-op. If a racer finishes before
/// `begin` installs the continuation, the first result is stashed and delivered
/// on `begin` — so the continuation is resumed exactly once, never lost, never
/// twice.
private final class DeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?
    private var resumed = false

    /// Installs the timeout leg on `clock` and suspends until whichever leg
    /// resolves first: the operation (launched by the caller and reporting
    /// through `finish`) or the deadline. `onError` tidies up a cancellable
    /// operation (a detached write) on timeout or the operation's own failure; a
    /// GCD-dispatched read passes nothing, as there is nothing to cancel.
    func awaitDeadline(
        seconds: Double,
        clock: any SleepClock,
        onError: @escaping @Sendable () -> Void = {}
    ) async throws -> T {
        let deadline = Task.detached {
            do {
                try await clock.sleep(for: seconds)
                self.finish(.failure(DeadlineExceeded.timedOut))
            } catch {
                // The operation won the race and this sleep was cancelled.
            }
        }
        do {
            let value = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                self.begin(continuation)
            }
            deadline.cancel()
            return value
        } catch {
            onError()
            deadline.cancel()
            throw error
        }
    }

    func begin(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        if let result = pendingResult {
            resumed = true
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        if let continuation {
            resumed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else if pendingResult == nil {
            pendingResult = result
            lock.unlock()
        } else {
            lock.unlock()
        }
    }
}
