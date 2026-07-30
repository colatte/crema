import Foundation

/// Runs a blocking synchronous C call without occupying a Swift concurrency
/// thread, and suspends the caller until it returns.
///
/// An `async` signature is not proof of a suspension point. A function declared
/// `async` whose body is a straight-line C call never suspends: it runs to
/// completion on whatever thread picked it up. WHICH thread that is depends on one
/// upcoming feature, and the hop below is the right answer under either. Absent
/// `NonisolatedNonsendingByDefault` — this project's state today — a nonisolated
/// `async` function switches to the generic concurrent executor on entry, so the
/// thread it burns is a cooperative-pool one whether the call came from a detached
/// task or from a `@MainActor` one. Under that flag (SE-0461, implemented in Swift
/// 6.2, opt-in today and the default in a future language mode) it stays on its
/// caller's actor instead, and the same straight-line C call blocks the MAIN THREAD
/// outright. The hazard changes address; only an explicit hop off answers both.
///
/// That matters because the cooperative pool has a fixed width (one thread per
/// core) and does not overcommit. Enough blocked calls and nothing scheduled on
/// Swift concurrency runs again, including the very deadline meant to abandon
/// them: the deadline sleeps on that same pool, so an exhausted pool leaves the
/// apply chain hung with the user's keys still consumed. GCD's global queue
/// spawns threads when its own block, so a call parked here costs a thread
/// rather than the app's concurrency.
///
/// The read side of the apply/verify cycle has followed this rule from the start
/// (`raceReadDeadline`); the write side did not, because its actuators *looked*
/// async. Every border that wraps a blocking C call belongs here.
/// (docs/DECISIONS.md: async-signature-is-not-a-suspension-point)
///
/// A call that never returns keeps the continuation and one GCD thread until it
/// does — the same bounded, honest residual the read side accepts. There is
/// nothing to cancel: a blocked C call cannot observe cancellation, so callers
/// bound it with a deadline and abandon it rather than waiting.
///
/// `queue` defaults to the global pool, whose width grows as its own threads
/// block. A caller passes its own SERIAL queue when the calls need ordering
/// against each other on top of a thread that may block: one border's readings
/// have to register in the order they were asked for, or a slow read lands a
/// stale value after a fast newer one. The trade is explicit — a blocked call
/// then holds that queue — so only work already meant to run one-at-a-time
/// belongs on it (PolledBrightnessSource, one reader per channel).
func blockingCall<T: Sendable>(
    on queue: DispatchQueue = .global(),
    _ body: @escaping @Sendable () throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        queue.async {
            continuation.resume(with: Result { try body() })
        }
    }
}

/// The non-throwing shape, so a call that cannot fail is not forced through
/// `try` — the actuators throw, an image decode answers nil.
func blockingCall<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(returning: body()) }
    }
}
