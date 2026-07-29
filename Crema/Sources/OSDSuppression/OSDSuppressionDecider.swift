import Foundation

/// Implementation details of MediaKeyInterceptionOSDSuppressor, split out only
/// to keep that file focused. Both types are its private collaborators.

/// Mutable per-domain probe bookkeeping. A reference type so a kick can flip
/// `probeImmediately` on the instance the running loop re-reads. Present in the
/// suppressor's `probes` dictionary exactly while its domain is suspended.
@MainActor
final class DomainProbe {
    var task: Task<Void, Never>?
    /// Index into the backoff schedule; advanced after each parked probe wait.
    var backoffAttempt = 0
    /// Consecutive probe failures with the channel present — the escalation
    /// counter. Device-absent failures never touch it; a recovery discards the
    /// whole DomainProbe, so recovery resets it.
    var channelPresentFailures = 0
    var longSuspended = false
    /// Set by a key-press kick; the next loop turn probes without waiting.
    var probeImmediately = false
}

/// The consumer's synchronous, thread-safe view of which domains are suspended,
/// plus the set of keys whose key-down was swallowed (so the matching key-up is
/// swallowed too — a leaked up after a swallowed down orphans the pair in the
/// system's key pairing). The MainActor mutates the suspended set
/// (suspend/resume/reset); the @Sendable consumer closure reads it and updates
/// the swallowed-downs set, both under one lock. Deliberately not
/// MainActor-isolated: the tap callback runs the closure synchronously off the
/// actor, and `MainActor.assumeIsolated` there would trap under the test fakes.
final class SuppressionDecider: @unchecked Sendable {
    private let lock = NSLock()
    private var suspended: Set<OSDSuppressionDomain> = []
    private var swallowedDowns: Set<MediaKey> = []

    func isSuspended(_ domain: OSDSuppressionDomain) -> Bool {
        lock.withLock { suspended.contains(domain) }
    }

    func suspendedSnapshot() -> Set<OSDSuppressionDomain> {
        lock.withLock { suspended }
    }

    /// Suspending also releases any held key in that domain, and the asymmetry
    /// behind that is the whole point.
    ///
    /// Without it, a key HELD across the suspension keeps being swallowed for the
    /// rest of the hold — every autorepeat down consumed, every apply dropped by
    /// the suspension guard — so the user gets no bar of ours and no native OSD
    /// either. Holding volume-down while AirPods drop is exactly that: press,
    /// nothing, until they let go.
    ///
    /// Releasing the latch means the pending up passes through as well, so a quick
    /// tap that suspends between its down and its up leaves the system an up with
    /// no down. That is the direction to err in. The alternative — keeping the up
    /// swallowed while letting the repeats through — leaves the system DOWNS with
    /// no up, and a media-key down with no up is what starts an autorepeat nobody
    /// stops: the volume would keep travelling on its own. An orphan up only ever
    /// ends a repeat that was never running.
    func suspend(_ domain: OSDSuppressionDomain) {
        lock.withLock {
            suspended.insert(domain)
            swallowedDowns = swallowedDowns.filter { OSDSuppressionDomain($0) != domain }
        }
    }

    func resume(_ domain: OSDSuppressionDomain) {
        lock.withLock { _ = suspended.remove(domain) }
    }

    func reset() {
        lock.withLock {
            suspended.removeAll()
            swallowedDowns.removeAll()
        }
    }

    /// Swallow decision for one event. A held key keeps the phase it committed to
    /// at its first down: once swallowed, every autorepeat stays swallowed and the
    /// matching up is swallowed too, so the system never sees half a press. A fresh
    /// key-down on a suspended domain passes through (and the caller kicks a
    /// probe) — as does a HELD one, because `suspend` drops the latch for its
    /// domain, which is what keeps a suspension from muting the rest of a hold.
    func decide(key: MediaKey, isDown: Bool) -> Bool {
        let domain = OSDSuppressionDomain(key)
        return lock.withLock {
            if isDown {
                if swallowedDowns.contains(key) { return true }
                if suspended.contains(domain) { return false }
                swallowedDowns.insert(key)
                return true
            } else {
                return swallowedDowns.remove(key) != nil
            }
        }
    }
}
