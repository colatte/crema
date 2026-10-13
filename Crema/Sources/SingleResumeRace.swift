import Foundation

/// Single-resume guard for a race between an operation and a deadline, generic
/// over the failure channel: `Failure == Never` for a value race (a child
/// process's exit, a neighbour app's answer), `Failure == any Error` for the
/// throwing races the OSD suppressor bounds its applies and reads with. One
/// copy, at the Sources root like `BlockingCall`: a shared rule restated per
/// copy lets a fix land in two and miss the third
/// (docs/DECISIONS.md: shared-skin-skeleton).
///
/// Either racer may finish on any thread (the operation on a detached task or a
/// GCD queue, the deadline on the injected clock), so the guard is lock-based
/// rather than actor-bound: the first result wins, the rest no-op, and a late
/// orphan is pure — its result dropped. A result arriving before `begin`
/// installs the continuation is stashed and delivered on begin, so the
/// continuation resumes exactly once — never lost, never twice.
///
/// Ordering lesson, owned by `armDeadline` below: on timeout, commit the
/// timed-out result through `finish` BEFORE any unwind of the abandoned operation
/// (a kill, a cancel). Unwinding first lets the dying operation's own late
/// `finish` race the timeout's for the single resume, leaking its value out of a
/// timed-out race.
final class SingleResumeRace<T: Sendable, Failure: Error>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Failure>?
    private var pendingResult: Result<T, Failure>?
    private var resumed = false

    func begin(_ continuation: CheckedContinuation<T, Failure>) {
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

    func finish(_ result: Result<T, Failure>) {
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

extension SingleResumeRace where Failure == Never {
    /// A value race has no failure channel; the bare value reads better at the
    /// call sites than `.success(value)`.
    func finish(_ value: T) {
        finish(.success(value))
    }
}

extension SingleResumeRace {
    /// The deadline leg every race in the app arms, so its rules live once: after
    /// `seconds` on `clock` it commits `timedOut`, and only then runs `onTimeout`
    /// (the ordering lesson above). A cancelled sleep commits nothing — the
    /// operation won, or the caller is tearing the race down — because a timeout
    /// committed there would be stashed and resolve the race with a deadline
    /// nobody reached. Detached, so the wait never pins the caller's actor; the
    /// caller cancels the returned task once the race is decided.
    func armDeadline(
        seconds: Double,
        on clock: any SleepClock,
        committing timedOut: Result<T, Failure>,
        then onTimeout: @escaping @Sendable () -> Void = {}
    ) -> Task<Void, Never> {
        Task.detached {
            do {
                try await clock.sleep(for: seconds)
            } catch {
                return
            }
            self.finish(timedOut)
            onTimeout()
        }
    }
}
