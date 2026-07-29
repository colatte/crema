import Foundation

/// Runs a blocking synchronous C call without occupying a Swift concurrency
/// thread, and suspends the caller until it returns.
///
/// An `async` signature is not proof of a suspension point. A function declared
/// `async` whose body is a straight-line C call never suspends: it runs to
/// completion on whatever thread picked it up. And because a nonisolated `async`
/// function hops off its caller's actor onto the global concurrent executor, the
/// thread it occupies is a cooperative-pool thread — no matter whether the call
/// came from a detached task or from a `@MainActor` one.
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
func blockingCall<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            continuation.resume(with: Result { try body() })
        }
    }
}
