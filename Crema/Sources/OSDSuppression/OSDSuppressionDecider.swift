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

    func suspend(_ domain: OSDSuppressionDomain) {
        lock.withLock { _ = suspended.insert(domain) }
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

    /// Swallow decision for one event. A held key keeps the phase it committed
    /// to at its first down: once swallowed, every autorepeat stays swallowed
    /// and the matching up is swallowed too. A fresh key-down on a suspended
    /// domain passes through (and the caller kicks a probe).
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
