import Foundation

/// Single-resume guard for a value-producing race between an operation and a
/// deadline. Either racer may finish on any thread (the operation on a detached
/// task, the deadline on the injected clock); the first result wins and the
/// rest no-op. A result arriving before `begin` installs the continuation is
/// stashed and delivered on begin, so the continuation resumes exactly once —
/// never lost, never twice. The value-returning sibling of the OSD suppressor's
/// throwing DeadlineRace.
final class SingleResumeRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    private var pending: T?
    private var resumed = false

    func begin(_ continuation: CheckedContinuation<T, Never>) {
        lock.lock()
        if let pending {
            resumed = true
            lock.unlock()
            continuation.resume(returning: pending)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ value: T) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        if let continuation {
            resumed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: value)
        } else if pending == nil {
            pending = value
            lock.unlock()
        } else {
            lock.unlock()
        }
    }
}

/// Races `operation` against a `timeout` on the injected clock. If the operation
/// completes first, its value is returned and the deadline is cancelled. If the
/// deadline fires first, `timedOutValue` is committed and `onDeadline` runs.
///
/// The operation task is deliberately never cancelled: it wraps an uncancellable
/// `withCheckedContinuation` (a child process's termination handler), which
/// cancellation cannot unblock — so `onDeadline` must force it to unwind (kill
/// the process → its termination handler fires → the parked continuation
/// resumes). Single-resume, so the loser's late completion is discarded. This is
/// the pure race logic tested with fake operations; the real subprocess wiring
/// lives in `runChildProcess` (docs/DECISIONS.md: child-process-deadline).
func raceAgainstDeadline<T: Sendable>(
    _ operation: @escaping @Sendable () async -> T,
    timeout: Double,
    clock: any SleepClock,
    timedOutValue: T,
    onDeadline: @escaping @Sendable () -> Void
) async -> T {
    let race = SingleResumeRace<T>()
    let work = Task.detached {
        let value = await operation()
        race.finish(value)
    }
    let deadline = Task.detached {
        do {
            try await clock.sleep(for: timeout)
            // Commit the timed-out value BEFORE the kill: onDeadline unwinds
            // the abandoned operation (kill → termination handler → its own
            // finish on another thread), and with the kill first that late
            // finish raced this one for the single resume — the hung path
            // must deterministically return timedOutValue, never whatever the
            // killed child's exit happens to interpret to.
            race.finish(timedOutValue)
            onDeadline()
        } catch {
            // The operation won; this sleep was cancelled.
        }
    }
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        race.begin(continuation)
    }
    deadline.cancel()
    // `work` is never cancelled — see the note above; it completes on its own
    // once onDeadline unwinds it, and its late result no-ops on the race.
    _ = work
    return result
}

/// How long a force-terminated child gets to honor SIGTERM before SIGKILL.
private let childProcessKillGrace: Double = 0.5

/// Runs a short-lived child `process` to completion under a `timeout`, mapping
/// its exit to a value via `interpret`. When `pipe` is given its stdout is read
/// once at exit (a single short line — safe off the main thread). If the
/// deadline fires first the process is force-terminated (SIGKILL after a short
/// grace if it ignores SIGTERM, so a genuinely stuck child's termination handler
/// is guaranteed to fire) and `failureValue` is returned; a spawn failure
/// returns `failureValue` too. This is the thin border around the child wait;
/// the race it delegates to is pure (docs/DECISIONS.md: child-process-deadline).
func runChildProcess<T: Sendable>(
    _ process: Process,
    readingStdout pipe: Pipe? = nil,
    timeout: Double,
    clock: any SleepClock,
    failureValue: T,
    interpret: @escaping @Sendable (Process, String?) -> T
) async -> T {
    await raceAgainstDeadline(
        {
            await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
                process.terminationHandler = { finished in
                    let output = pipe.flatMap { pipe -> String? in
                        let data = try? pipe.fileHandleForReading.readToEnd()
                        return data
                            .flatMap { String(data: $0, encoding: .utf8) }?
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    continuation.resume(returning: interpret(finished, output))
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: failureValue)
                }
            }
        },
        timeout: timeout,
        clock: clock,
        timedOutValue: failureValue,
        onDeadline: { [clock] in
            guard process.isRunning else { return }
            process.terminate()
            Task.detached {
                try? await clock.sleep(for: childProcessKillGrace)
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    )
}
