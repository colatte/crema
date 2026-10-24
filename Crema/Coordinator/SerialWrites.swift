/// One actuator's drag writes, each started only after the one before it has
/// returned, so the level the finger stopped at is the last one to land.
///
/// Ordering is not something the writes have on their own. Each drag frame is a
/// task of its own, the actuator's `async` entry hops off the main actor, and the
/// blocking call under it goes to `DispatchQueue.global()`, where "Tasks
/// submitted to the returned queue are scheduled concurrently with respect to one
/// another" (Apple, DispatchQueue.global(qos:)). A slow write can therefore land
/// after a faster, newer one and leave the output at a level the finger already
/// left. The order is kept here, above the actuator, and the blocking call stays
/// on the global queue, whose threads grow under blocking, so the key path's
/// deadlines are untouched (docs/DECISIONS.md: J3-deadline-cooperativo).
///
/// A write that never returns holds the writes queued behind it, on that actuator
/// only: they wait as suspended tasks, not as blocked threads.
@MainActor
final class SerialWrites {
    /// Waits for the newest write enqueued so far.
    private var last: (@Sendable () async -> Void)?

    /// Runs `write` once every write enqueued before it has finished; the task is
    /// returned for a caller that needs the write's own answer.
    @discardableResult
    func enqueue<T: Sendable>(_ write: @escaping @MainActor () async -> T) -> Task<T, Never> {
        let previous = last
        let next = Task { @MainActor in
            await previous?()
            return await write()
        }
        last = { _ = await next.value }
        return next
    }
}
