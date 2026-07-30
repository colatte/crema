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
    /// Controls a channel has already answered it does not have. A third input to
    /// the same verdict, alongside the suspended set and the caller's `canApply`,
    /// and it lives here for two reasons that are not style. It is asked from the
    /// TAP thread synchronously, so it needs exactly the lock this type already
    /// owns — a second lock beside it would be a second take per press. And marking
    /// an absence must release that key's swallow latch in the SAME lock take (see
    /// `noteAbsentCapability`), which is only atomic if both live here.
    ///
    /// Not a suspension and never confused with one: nothing is broken, so there is
    /// no probe, no escalation and no menu (docs/DECISIONS.md:
    /// absent-capability-hands-the-key-back).
    private var absentCapabilities: Set<OSDSuppressionCapability> = []

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

    /// Records that a channel answered "no such control" during an apply, and
    /// releases any held key of that capability in the same lock take.
    ///
    /// The release is not optional, and pairing it here rather than at the call site
    /// is the whole reason this state lives in this type. `decide` commits a verdict
    /// at the first down and keeps it for the rest of the press, so a key HELD while
    /// the apply discovers the absence would stay swallowed until the user lets go:
    /// press, nothing, for the length of the hold. That is the identical dead
    /// gesture `suspend` releases the latch to avoid, and holding volume-down to
    /// zero on an output with no volume control is how a person meets it. Marking
    /// without releasing would deliver that bug through a second door.
    ///
    /// Filtered by CAPABILITY, never by domain: mute rides with volume for recovery,
    /// so a domain-wide release would free a held VOLUME key the moment the mute
    /// plane turned out to be missing. Inherits the same asymmetry `suspend` argues
    /// for — the pending up passes too, leaving the system an up with no down, which
    /// is the direction to err in, since an orphan up only ends a press nobody was
    /// tracking while an orphan down has no closing event at all.
    /// Returns whether this was NEW information, because one caller asks about a
    /// capability its own key is not gated on: volume-up re-reads the mute plane on
    /// every press it takes, so on a device whose LEVEL is fine that guard keeps
    /// answering forever. Without this edge the caller would write one log line per
    /// autorepeat, for the life of the process.
    ///
    /// The swallow latch is deliberately NOT dropped here, and that is where this
    /// parts company with `suspend`. Dropping it leaks the pending up: unlike a
    /// suspension — which needs a failure to land inside one press, a rare window
    /// its own rationale accepts — an absence is discovered BY the press that
    /// judges it, so the leak would be the MODAL outcome of every first tap. A
    /// quick tap would put a key-up on the system with no key-down before it.
    /// `decide` migrates the latch at the next down instead: a HELD key is released
    /// on its next autorepeat, so there is no dead gesture, and a tap that never
    /// repeats keeps both phases swallowed — the system sees nothing rather than
    /// half a press.
    @discardableResult
    func noteAbsentCapability(_ capability: OSDSuppressionCapability) -> Bool {
        lock.withLock { absentCapabilities.insert(capability).inserted }
    }

    func isCapabilityAbsent(_ capability: OSDSuppressionCapability) -> Bool {
        lock.withLock { absentCapabilities.contains(capability) }
    }

    /// Drops an absence so the next press is taken again. Clear-only by design, and
    /// that asymmetry is the safety: an absence is written only on the apply path,
    /// which is the only place that asks the channel, while a re-check that lands
    /// late with a stale "still missing" simply does not clear. So a stale answer
    /// can never make the app swallow a key on worse evidence than it already had —
    /// the failure mode of this whole axis points at handing keys to the system.
    func clearAbsentCapability(_ capability: OSDSuppressionCapability) {
        lock.withLock { _ = absentCapabilities.remove(capability) }
    }

    func reset() {
        lock.withLock {
            suspended.removeAll()
            swallowedDowns.removeAll()
            passedDowns.removeAll()
            // An engage/disengage flip is born healthy on every axis, and this one
            // is no exception: what the hardware could do before a lock or a toggle
            // says nothing about now, and re-learning costs one press.
            absentCapabilities.removeAll()
        }
    }

    /// Swallow decision for one event. A press commits to ONE verdict at its first
    /// down and keeps it through its autorepeats and its up, in BOTH directions, so
    /// the system never sees half a press. A fresh key-down passes when its domain
    /// is suspended (the caller kicks a probe), when its capability is known absent
    /// (nothing to write, so the system gets the key and draws its own answer), or
    /// when `canApply` is false — the caller's answer to whether this key's change
    /// is this app's to make at all, which today is the display under the pointer
    /// and asked only for screen brightness (docs/DECISIONS.md:
    /// brightness-key-follows-the-pointer). The three are different facts with
    /// different lifetimes — `canApply` is a live border reading taken at this very
    /// press, suspension is a failure awaiting a probe, absence is a control the
    /// hardware does not have — and they meet here because they produce one and the
    /// same verdict. A HELD key passes for the last two mid-hold as well, because
    /// `suspend` and `noteAbsentCapability` both drop its swallow latch, which is
    /// what keeps either of them from muting the rest of a hold.
    func decide(key: MediaKey, isDown: Bool, canApply: Bool) -> Bool {
        let domain = OSDSuppressionDomain(key)
        let capability = OSDSuppressionCapability(key)
        return lock.withLock {
            if isDown {
                // Absence is re-read ahead of the swallow latch, and only absence is:
                // it is the one verdict-changing fact discovered BY the press it
                // judges, so a held key would otherwise stay swallowed until the user
                // let go — press, nothing, for the length of the hold. Migrating the
                // key here rather than dropping it at the mark keeps the pair whole:
                // an autorepeat moves it to the passed set and the up follows, while
                // a tap that never repeats still finds its down latched and is
                // swallowed in both phases. The system gets a whole press or none.
                if absentCapabilities.contains(capability) {
                    swallowedDowns.remove(key)
                    passedDowns.insert(key)
                    return false
                }
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
