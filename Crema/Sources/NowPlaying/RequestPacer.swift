import Foundation

/// When the next request may leave, for an endpoint that publishes a rate limit.
///
/// Pure and separate because the whole correctness argument is arithmetic, and
/// because the one thing that must not be got wrong is invisible in the arithmetic:
/// the slot is **reserved** in the same breath it is read. An actor releases its
/// isolation at every `await`, so a version that read the last departure, slept,
/// and then recorded its own would let two callers read the same value and leave
/// together — the exact burst the limit exists to prevent.
struct RequestSchedule {
    /// Monotonic seconds, in whatever timebase the caller reads. Nil until the
    /// first reservation: a first request waits for nothing.
    private var nextDeparture: Double?

    /// Claims the earliest slot at or after `now` and returns how long the caller
    /// must wait for it. Never negative — a timebase that appears to move
    /// backwards must delay a request, not schedule one in the past.
    mutating func reserve(at now: Double, spacing: Double) -> Double {
        let slot = max(now, nextDeparture ?? now)
        nextDeparture = slot + spacing
        return max(0, slot - now)
    }
}

/// Keeps successive requests to one endpoint at least `spacing` apart.
///
/// MusicBrainz publishes a hard limit of one request per second per source IP,
/// and the app can exceed it honestly: a held next-key changes track faster than
/// that, and each change asks for a cover. Exceeding it costs 503s for this user
/// and, sustained, a block for every Crema user behind the same address — a price
/// paid by people who never touched the feature.
///
/// The Cover Art Archive itself states it has no rate limiting, so only the
/// metadata half of a lookup comes through here.
actor RequestPacer {
    private let spacing: Double
    private let clock: any SleepClock
    private let now: @Sendable () -> Double
    private var schedule = RequestSchedule()

    /// `systemUptime` rather than a wall clock: it cannot be dragged by an NTP
    /// correction or a timezone change into scheduling a burst. It also stops
    /// while the Mac is asleep, which is the conservative direction — the pacer
    /// believes less time passed than really did and waits longer.
    static let monotonicNow: @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }

    init(
        spacing: Double,
        clock: any SleepClock = ContinuousSleepClock(),
        now: @escaping @Sendable () -> Double = RequestPacer.monotonicNow
    ) {
        self.spacing = spacing
        self.clock = clock
        self.now = now
    }

    /// Returns when the caller may send. Cancellation is deliberately not
    /// observed here: the slot is already reserved, and abandoning the wait would
    /// only make the next caller sit out a gap nobody used. Callers check
    /// `Task.isCancelled` after this returns instead.
    func waitForTurn() async {
        let delay = schedule.reserve(at: now(), spacing: spacing)
        guard delay > 0 else { return }
        try? await clock.sleep(for: delay)
    }
}
