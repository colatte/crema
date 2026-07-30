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
/// plus the verdict each held key committed to at its first down, so the system
/// never sees half a press: a leaked up after a swallowed down — or a swallowed
/// up after a leaked down — orphans the pair in the system's key pairing. The
/// MainActor mutates the suspended set (suspend/resume/reset); the @Sendable
/// consumer closure reads it and updates the two latch sets, all under one lock.
/// Deliberately not MainActor-isolated: the tap callback runs the closure
/// synchronously off the actor, and `MainActor.assumeIsolated` there would trap
/// under the test fakes.
final class SuppressionDecider: @unchecked Sendable {
    private let lock = NSLock()
    private var suspended: Set<OSDSuppressionDomain> = []
    private var swallowedDowns: Set<MediaKey> = []
    /// Keys whose down was let THROUGH, so its autorepeats and its up go the same
    /// way. Needed because the reason a down passes can change under a held key:
    /// the pointer crosses onto another display (`canApply` flips) or a probe
    /// re-engages the domain mid-hold. Without this latch the rest of that press
    /// would be swallowed, leaving the system downs with no up — half a press with
    /// no closing event, the same orphaned pair the swallow latch already avoids in
    /// the other direction.
    private var passedDowns: Set<MediaKey> = []

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
    /// no up, which is the half of this type's pairing rule that has no closing
    /// event: nothing the system receives later ends that press. An orphan up only
    /// ever ends a press nobody was tracking. What is NOT at risk in either
    /// direction is the AUTOREPEAT — it is generated upstream of every CGEventTap,
    /// by a timer inside the HID event system that the physical key-down arms and
    /// the physical key-up cancels (IOHIDFamily: IOHIDKeyboardFilter.mm
    /// processKeyRepeats; IOHIKeyboard::setRepeat on the legacy path), so no tap
    /// ever sees those events, let alone swallows them.
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
            passedDowns.removeAll()
        }
    }

    /// Swallow decision for one event. A press commits to ONE verdict at its first
    /// down and keeps it through its autorepeats and its up, in BOTH directions, so
    /// the system never sees half a press. A fresh key-down passes when its domain
    /// is suspended (the caller kicks a probe) or when `canApply` is false — the
    /// caller's answer to whether this key's change is this app's to make at all,
    /// today the display under the pointer and only for screen brightness
    /// (docs/DECISIONS.md: brightness-key-follows-the-pointer). A HELD key on a
    /// domain suspended mid-hold passes too, because `suspend` drops its swallow
    /// latch, which is what keeps a suspension from muting the rest of a hold.
    func decide(key: MediaKey, isDown: Bool, canApply: Bool) -> Bool {
        let domain = OSDSuppressionDomain(key)
        return lock.withLock {
            if isDown {
                if swallowedDowns.contains(key) { return true }
                if passedDowns.contains(key) { return false }
                guard !suspended.contains(domain), canApply else {
                    passedDowns.insert(key)
                    return false
                }
                swallowedDowns.insert(key)
                return true
            } else {
                passedDowns.remove(key)
                return swallowedDowns.remove(key) != nil
            }
        }
    }
}
