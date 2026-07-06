/// Injectable waiting primitive for the Coordinator's display timers
/// (timers are cancellable Tasks; unit tests must never really
/// sleep — they inject a fake clock instead).
protocol SleepClock: Sendable {
    /// Suspends for `seconds`, throwing CancellationError if the Task is cancelled.
    func sleep(for seconds: Double) async throws
}

/// Real clock backed by Task.sleep.
struct ContinuousSleepClock: SleepClock {
    func sleep(for seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}
