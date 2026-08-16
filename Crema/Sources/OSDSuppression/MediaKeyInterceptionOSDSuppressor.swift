import Foundation
import os

// One cohesive class: apply + verify + per-domain suspension + the two recovery
// axes (read-driven probe, write-health flap). Its collaborators (DomainProbe,
// SuppressionDecider, the deadline machinery) are already split out; the rest is
// tightly coupled and large.
// swiftlint:disable file_length

/// Suppresses the native volume/brightness OSD by consuming the media keys:
/// the system never sees the key, so it never shows its HUD, and the app
/// becomes the only applier — the technique the ecosystem converged on for
/// macOS 26, where the redesigned OSD is rendered by ControlCenter: freezing
/// the old OSDUIHelper is a no-op there (measured on hardware — the per-key
/// popover kept appearing with the helper alive and SIGSTOPped), and
/// suspending ControlCenter itself is out of the question (it hosts the menu
/// bar and has KeepAlive), which is why the helper-suspension alternative was
/// rejected.
///
/// Reversible by construction: disengaging clears the tap's consumer, and the
/// tap itself dies with the process — toggle-off, quit or crash all restore
/// the native behavior instantly, with zero residue.
///
/// Production safety, in layers:
/// - Every consumed key is applied and then verified by reading the value
///   back. The first failure *suspends only that key's domain* (volume, screen
///   brightness, or keyboard brightness): its keys flow back to the system and
///   the native OSD gives the feedback, while the other domains keep being
///   suppressed. A cheap read-only probe on a backoff re-engages the domain
///   the moment the channel recovers — a device swap (AirPods dropping mid
///   volume-key) heals in seconds, silently. This replaced a global
///   auto-disengage that killed all three domains and persisted the opt-in off
///   on any single-channel failure; no failure path writes the pref now.
///   (docs/DECISIONS.md: per-domain-suspension / pref-sacred)
/// - Both the writes and the border reads race a deadline off the MainActor
///   (mechanism in OSDApplyDeadline). A hung actuator (coreaudiod stall,
///   Bluetooth output dropping mid-write) would strand the apply chain while
///   keys keep being consumed; a blocking synchronous C read
///   (AudioObjectGetPropertyData, DisplayServicesGetBrightness) run inline would
///   be worse — freezing the whole app (HUD, now playing, menu) and wedging the
///   queue (the deadline covers the pre-read, read-back, mute-plane reads and every
///   capability guard that can block: the volume and mute guards are Core Audio IPC,
///   and the keyboard-backlight guard enumerates the backlight IDs over the private
///   client's connection, so it is IPC too. Only the SCREEN-brightness guard stays
///   inline, because DisplayServices answers it from two dlsym results resolved once
///   at init and it cannot block; docs/DECISIONS.md: read-deadline-pool-rule).
///   On timeout the domain is suspended and the operation
///   abandoned; a late orphan is bounded and pure — a write moves the value one
///   step with no HUD (the consumed press's own intent), a read writes nothing —
///   because the domain is suspended and the queued keys fall through the
///   suspension guard rather than starting new work.
///   The chain is ONE chain: applies are serialized globally so an autorepeat burst
///   cannot re-read the same base value twice, which means a hung write on one
///   channel also delays the next consumed key of every OTHER domain. Accepted, and
///   bounded twice — the deadline abandons the hung write, and the failure suspends
///   only the channel that hung, so its keys go back to the system instead of
///   entering the chain again. A per-domain chain would be the honest shape (volume
///   and brightness never share a base value), and is not worth the pending/generation
///   state it would triple for a bounded 2 s worst case
///   (docs/DECISIONS.md: per-domain-suspension).
/// - An absent capability is not a failure: outputs without a volume/mute
///   control and Macs without a keyboard backlight have nothing malfunctioning and
///   nothing for a probe to recover, so they never suspend a domain and never reach
///   the menu. They do not stay SWALLOWED either — the key goes back to the system,
///   which applies it and draws its own indicator, because a consumed key always
///   owes feedback and this app has none to give for a control that does not exist.
///   The absence is learned on the apply, the only place that asks the channel, and
///   read at the next press, so the first press of an episode is the mute one that
///   buys the answer; a key held across that press is released at its next
///   autorepeat, when `decide` reads the mark and migrates the latch, or the whole
///   hold would go dead — and a tap that never repeats stays swallowed in both
///   phases rather than leaking a bare up
///   (docs/DECISIONS.md: absent-capability-hands-the-key-back).
@MainActor
final class MediaKeyInterceptionOSDSuppressor: NativeOSDSuppressor {
    /// Generous against slow-but-alive devices (Bluetooth volume writes can
    /// take hundreds of ms); a genuinely hung actuator still fails soon
    /// enough for the user to associate cause and effect.
    nonisolated static let defaultApplyDeadline: Double = 2.0

    /// Recovery-probe backoff: 1, 2, 4, 8, 16 s, then 30 s forever. The first
    /// three cover the typical AirPods/output-swap window (<5 s), re-engaging
    /// in silence; the 30 s cap keeps the self-heal eternal and cheap.
    private static let probeBackoffSchedule: [Double] = [1, 2, 4, 8, 16]
    private static let probeBackoffCap: Double = 30

    /// After this many consecutive *scheduled* probe failures with the channel
    /// present (~31 s of accumulated backoff), a domain is long-suspended and
    /// surfaces in the menu. Neither a device-absent probe nor a key-kicked
    /// immediate probe counts toward it — kicks only speed recovery, so letting
    /// them count would collapse this window to sub-second on a hammered dead
    /// key.
    nonisolated static let escalationThreshold = 5

    /// The write-health axis counts apply-failure *episodes* (a verified write
    /// that never moved, or a write that hung past the deadline), reset only by a
    /// verified apply — a different measure from `escalationThreshold`, which
    /// counts *scheduled* backoff probes and so encodes the ~31 s recovery
    /// window. They share the value 5 but do not share a meaning: one key press
    /// drives at most one write-health episode, so this threshold is a count of
    /// failed applies, not a span of time. Named separately so the two axes are
    /// not silently coupled through one constant.
    static let writeHealthEscalationThreshold = 5

    private static func probeBackoff(attempt: Int) -> Double {
        attempt < probeBackoffSchedule.count ? probeBackoffSchedule[attempt] : probeBackoffCap
    }

    private let keys: any MediaKeyConsuming
    private let volume: any OSDVolumeChannel
    private let screen: any OSDChannel
    private let keyboard: any OSDChannel
    /// Which display a screen-brightness key would land on, asked at the press. A
    /// closure because the answer is a border reading (the live cursor plus the
    /// active display list) and this type stays testable without either; called on
    /// the tap thread, so it is Sendable and never hops.
    private let screenBrightnessTarget: @Sendable () -> BrightnessKeyTarget
    private let clock: any SleepClock
    /// Clock the read deadline sleeps on. Separate from `clock` only for tests:
    /// read deadlines fire on the recovery-probe path too (probeOutcome's
    /// reads), which runs while a domain's backoff is scheduled on `clock`, so
    /// keeping them apart lets a test advance the probe backoff without tripping
    /// a read deadline and vice-versa. In production both are real clocks and
    /// the split is immaterial.
    private let readClock: any SleepClock
    private let applyDeadline: Double

    private(set) var isEngaged = false
    /// Fired after each verified apply on a healthy domain — AppCore pokes the
    /// matching brightness sampler so the app's HUD shows the post-apply value
    /// (Core Audio is event-driven and needs no poke; the media-key router's
    /// key-time poke still gives the HUD its instant appearance).
    var onApplied: (@MainActor (MediaKey) -> Void)?

    /// Fired when a key was handed back to the system, for any of the three
    /// reasons this app has one: the pointer rule declined it, the key's control
    /// is known absent on this route, or its domain is suspended after a failed
    /// apply. The seam does not tell them apart because the consequence is
    /// identical and is the only thing the owner acts on — somebody else draws
    /// that press, so AppCore spends the local brightness source's key window
    /// with this. Otherwise the tap's own observation arms a poll, the poll
    /// reads the value macOS just moved, and the app puts a second bar over the
    /// native indicator. Same seam the neighbour's report uses (docs/DECISIONS.md:
    /// betterdisplay-osd-source, absent-capability-hands-the-key-back,
    /// per-domain-suspension).
    var onHandedBackToTheSystem: (@MainActor (MediaKey) -> Void)?

    private(set) var longSuspendedDomains: Set<OSDSuppressionDomain> = []
    var onSuspensionStateChange: (@MainActor () -> Void)?

    /// Every currently suspended domain (transient or long). Introspection
    /// surface — the menu only reads `longSuspendedDomains`.
    var suspendedDomains: Set<OSDSuppressionDomain> { decider.suspendedSnapshot() }

    /// The consumer's synchronous, thread-safe view of suspension. Read off the
    /// MainActor in the tap callback; mutated on the MainActor here.
    private let decider = SuppressionDecider()
    /// Per-domain recovery-probe state; a domain has an entry iff it is
    /// suspended.
    private var probes: [OSDSuppressionDomain: DomainProbe] = [:]

    /// Consecutive read-OK/write-dead apply failures not yet cleared by a
    /// verified apply — the WRITE-health escalation axis, orthogonal to the
    /// probe's read-driven `channelPresentFailures`. Fed only by the signatures a
    /// read-only probe cannot detect: a write the actuator accepted that never
    /// moved (`verificationFailed`) or a write that hung past the deadline
    /// (`writeTimedOut`). A read-side failure — a nil read (`currentValueUnreadable`)
    /// or a stalled read (`readTimedOut`) — deliberately does NOT feed this axis:
    /// the recovery probe reads, so it already owns that failure, and counting it
    /// here would both double-count it and mislabel a read stall as a dead write.
    /// The recovery probe is read-only by design (re-driving a write would flip
    /// the value under the user), so it proves only the READ path: a channel whose
    /// read is healthy but whose write is persistently dead (the post-wake ramp
    /// re-asserting brightness, True Tone overriding the value) is re-engaged by
    /// every probe and re-suspended by the very next key — a flap
    /// `channelPresentFailures` never escalates, since the probe keeps
    /// "recovering" and each recovery discards the whole DomainProbe. This counter
    /// survives the optimistic re-engage and is reset only by a verified apply
    /// (the sole proof the write is alive), so a write-dead/read-OK channel
    /// surfaces in the menu instead of flapping in silence (the reported
    /// regression).
    private var unconfirmedApplyFailures: [OSDSuppressionDomain: Int] = [:]

    /// Applies run strictly in key order: an autorepeat burst over async
    /// applies would otherwise read the same base value twice and lose steps.
    private var pending: Task<Void, Never>?
    /// Bumped on every engage/disengage flip (never on a per-domain suspend).
    /// Chain entries and probe loops carry the generation they were created
    /// under and no-op once it moves on — a bare isEngaged check would let a
    /// key consumed just before a disengage apply after a rapid re-engage.
    private var generation = 0

    private let logger = Logger.crema("OSD")

    /// `screenBrightnessTarget` has no default on purpose. A default would be the
    /// built-in panel, which is exactly the behaviour that dimmed the laptop while
    /// the user read the monitor — and a construction that dropped the argument
    /// would restore that bug with the whole suite green. Making it required turns
    /// an untestable wiring risk into a compile error.
    init(
        keys: any MediaKeyConsuming,
        volume: any OSDVolumeChannel,
        screen: any OSDChannel,
        keyboard: any OSDChannel,
        screenBrightnessTarget: @escaping @Sendable () -> BrightnessKeyTarget,
        clock: any SleepClock = ContinuousSleepClock(),
        readClock: any SleepClock = ContinuousSleepClock(),
        applyDeadline: Double = MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline
    ) {
        self.keys = keys
        self.volume = volume
        self.screen = screen
        self.keyboard = keyboard
        self.screenBrightnessTarget = screenBrightnessTarget
        self.clock = clock
        self.readClock = readClock
        self.applyDeadline = applyDeadline
    }

    func setEngaged(_ engaged: Bool) {
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        generation += 1
        if engaged {
            // Fresh engagement: every domain healthy, no in-flight suspension.
            decider.reset()
            unconfirmedApplyFailures.removeAll()
            // The generation is baked into the consumer at install time: a
            // key consumed under this engagement hops to the main actor
            // carrying it, so a disengage/re-engage landing before the hop
            // cannot adopt the stale key into the new engagement.
            let installedGeneration = generation
            keys.setConsumer { [weak self] key, fine, isDown in
                guard let self else { return false }
                // The swallow decision is synchronous and must be made here, on
                // the tap thread; the side effects (apply, probe kick) hop to
                // the main actor. Where the key would LAND is read here for the
                // same reason — the answer is where the pointer is right now, and
                // there is no hop available to go and ask. Only a down can change a
                // verdict, since the decider latches it for the rest of the press,
                // so only a down pays the reading.
                let canApply = isDown ? self.canApplyHere(key) : true
                let swallow = self.decider.decide(key: key, isDown: isDown, canApply: canApply)
                if isDown {
                    Task { @MainActor in
                        self.handleConsumedDown(key, fine: fine, swallowed: swallow, generation: installedGeneration)
                    }
                }
                return swallow
            }
            logger.info("native-OSD suppression engaged")
        } else {
            // Nil restores pure observation — the whole reversibility story.
            // A disengage (lock or toggle-off) is coarser than a per-domain
            // suspension: it cancels every probe and clears all domain state,
            // so re-engaging is born fully healthy, exactly like a relaunch.
            keys.setConsumer(nil)
            cancelAllProbes()
            decider.reset()
            unconfirmedApplyFailures.removeAll()
            if !longSuspendedDomains.isEmpty {
                longSuspendedDomains.removeAll()
                onSuspensionStateChange?()
            }
            logger.info("native-OSD suppression disengaged")
        }
    }

    /// The pointer's half of the swallow decision: whether this key's change is
    /// this app's to make at all. Screen brightness is the only domain a display
    /// can own — volume belongs to no display, the backlight to the one keyboard —
    /// and this app reads and writes the built-in panel and no other, so a key
    /// aimed anywhere else goes back to whoever can move that screen (a display
    /// utility behind us in the tap chain, or macOS), each of which draws its own
    /// feedback. Swallowing it would move a screen the user is not looking at, or
    /// eat a press and draw nothing
    /// (docs/DECISIONS.md: brightness-key-follows-the-pointer). Nonisolated because
    /// the tap thread asks it synchronously at the press; it reads nothing but the
    /// injected border closure, which is why the other two reasons a key is handed
    /// back are NOT here: a domain suspended after a failed apply and a control the
    /// channel already answered it does not have are both memory rather than a live
    /// reading, and both live under the decider's one lock, so the tap takes a
    /// single lock per press and this stays a pure border question.
    private nonisolated func canApplyHere(_ key: MediaKey) -> Bool {
        guard OSDSuppressionDomain(key) == .screenBrightness else { return true }
        return screenBrightnessTarget() == .builtIn
    }

    private func handleConsumedDown(_ key: MediaKey, fine: Bool, swallowed: Bool, generation: Int) {
        guard generation == self.generation, isEngaged else { return }
        if swallowed {
            enqueue(key, fine: fine, generation: generation)
            return
        }
        let domain = OSDSuppressionDomain(key)
        if decider.isSuspended(domain) {
            // A suspended domain's key passed to the system; an active user
            // pressing it is a cue to try recovering now, ahead of the backoff.
            // The seam below still fires: the press is the system's to draw, and
            // suspension changes only WHO recovers, never who owes the feedback.
            kickProbe(domain)
        } else {
            // Passed with the domain healthy, which leaves the other two reasons
            // this app hands a key back: the pointer rule declined it, or its
            // control is known absent. Still derived from the state rather
            // than carried down from the tap, so an autorepeat that passes on the
            // LATCH — after the pointer has already crossed back — stands down too;
            // otherwise the router's poll re-arms mid-hold and the local bar returns
            // over the system's own indicator.
            let capability = OSDSuppressionCapability(key)
            if decider.isCapabilityAbsent(capability) {
                // The user's next press IS the invalidation: no timer, no probe. The
                // fact only changes when hardware does, and a press proves an active
                // user is there to notice the recovery. Gated on the capability
                // actually being marked so a key the POINTER declined never pays a
                // border read — that path costs nothing today and must keep costing
                // nothing under autorepeat.
                recheckCapability(capability, generation: generation)
            }
        }
        onHandedBackToTheSystem?(key)
    }

    /// Capabilities with a re-check in flight. Autorepeat arrives at the HID timer's
    /// cadence, not the user's, so without this every repeat of a handed-back key
    /// would start its own border read; the probe's kick is coalesced the same way.
    /// MainActor-only state, like every other field here.
    private var rechecksInFlight: Set<OSDSuppressionCapability> = []

    /// Asks the channel whether the missing control came back — off the MainActor,
    /// read-only, and clear-only.
    ///
    /// Off the MainActor because it must be: in production the tap callback is
    /// delivered on the main run loop, so this hop lands on the same thread the tap
    /// uses, and the volume/mute guards are Core Audio IPC while the keyboard guard
    /// enumerates over the private client's connection. Asked inline, that is a
    /// blocking round trip once per press (docs/DECISIONS.md: read-deadline-pool-rule
    /// — a blocking call raced against a deadline runs on the GCD global queue, never
    /// on the cooperative pool, which the deadline itself sleeps on).
    ///
    /// Read-only because the key already went to the system, which applied it; a
    /// re-apply here would move the value twice for one press. Clear-only because a
    /// stale or timed-out answer must never re-assert an absence: a stall is not an
    /// answer, so the mark stays and the key keeps going to the system, which is the
    /// safe side to be wrong on.
    private func recheckCapability(_ capability: OSDSuppressionCapability, generation: Int) {
        guard rechecksInFlight.insert(capability).inserted else { return }
        Task { [weak self] in
            await self?.runCapabilityRecheck(capability, generation: generation)
        }
    }

    private func runCapabilityRecheck(_ capability: OSDSuppressionCapability, generation: Int) async {
        defer { rechecksInFlight.remove(capability) }
        guard let present = try? await readWithDeadline(capabilityGuard(capability)), present else { return }
        // The read awaited: a disengage may have landed, and a fresh engagement was
        // already born with no absences at all, so clearing under a stale generation
        // would be writing into a world that no longer exists.
        guard generation == self.generation, isEngaged else { return }
        decider.clearAbsentCapability(capability)
        logger.info("\(String(describing: capability), privacy: .public) reports a control again — its key is ours to take once more")
    }

    /// The one border question each capability answers. Sendable and closed over the
    /// channel alone, because it is handed to the deadline racer and runs on a GCD
    /// thread, never here.
    private func capabilityGuard(_ capability: OSDSuppressionCapability) -> @Sendable () -> Bool {
        switch capability {
        case .volumeLevel: return { [volume] in volume.isAvailable() }
        case .mute: return { [volume] in volume.supportsMute() }
        case .screenBrightness: return { [screen] in screen.isAvailable() }
        case .keyboardBrightness: return { [keyboard] in keyboard.isAvailable() }
        }
    }

    private func enqueue(_ key: MediaKey, fine: Bool, generation: Int) {
        guard generation == self.generation, isEngaged else { return }
        let previous = pending
        pending = Task { [weak self] in
            await previous?.value
            await self?.applyVerified(key, fine: fine, generation: generation)
        }
    }

    private enum ApplyFailure: Error {
        /// A read returned nil (read-side). The recovery probe owns this.
        case currentValueUnreadable
        /// A read stalled past the deadline (read-side). The probe owns this.
        case readTimedOut
        /// The actuator accepted the write but the value never moved
        /// (read-OK/write-dead). Feeds the write-health axis.
        case verificationFailed
        /// The write itself hung past the deadline (read-OK/write-hung). Feeds
        /// the write-health axis.
        case writeTimedOut
    }

    /// The read-OK/write-dead signatures the read-only recovery probe cannot
    /// prove, and so the only ones that feed the write-health escalation axis. A
    /// read-side failure is the probe's own axis (`channelPresentFailures`);
    /// counting it here would double-count it and mislabel a read stall as a dead
    /// write.
    private static func isWriteHealthFailure(_ error: Error) -> Bool {
        guard let failure = error as? ApplyFailure else { return false }
        switch failure {
        case .verificationFailed, .writeTimedOut: return true
        case .currentValueUnreadable, .readTimedOut: return false
        }
    }

    /// A consumed key whose channel reports no capability (an HDMI/USB output
    /// without a volume or mute control, a Mac without a keyboard backlight, the
    /// private symbols never resolving) is not a failure and does not suspend —
    /// there is nothing malfunctioning to report and nothing for a probe to
    /// recover, so it never counts toward escalation and never reaches the menu.
    ///
    /// What it must not do is stay swallowed. This apply wrote nothing and drew
    /// nothing, and the tap had already eaten the press, so the user got no answer
    /// at all — the one place this app broke its own rule that a consumed key owes
    /// feedback. Recording the absence is what closes it: the next press reads the
    /// mark before the tap decides, the key goes to the system, and the system
    /// applies it and draws its own indicator. THIS press is the one that pays for
    /// the answer, and a key held through it is released at its next autorepeat,
    /// when `decide` reads the mark and migrates the latch — not here, at the mark,
    /// which would leak the pending up on every first tap.
    ///
    /// Per CAPABILITY, never per domain: mute rides with volume for recovery, so
    /// marking the domain would hand back the volume keys of a device whose level
    /// works and whose mute plane simply does not exist. Cleared by a re-check that
    /// proves the control back, or by an engage/disengage flip, which is born
    /// healthy like every other axis (docs/DECISIONS.md:
    /// absent-capability-hands-the-key-back).
    ///
    /// The log line is no longer deduplicated for the life of the process: once the
    /// mark is set the key stops being swallowed, so no apply runs to log again, and
    /// the recurring case worth seeing — a route that loses a control, gets it back
    /// and loses it again — leaves one line per episode instead of one forever.
    private func noteAbsent(_ capability: OSDSuppressionCapability, generation: Int) {
        // The only write in this file that lands AFTER an await without re-checking
        // the generation, until now — and its clearing sibling (`runCapabilityRecheck`)
        // already re-checks, which is the asymmetry that gave it away. An engage flip
        // in the window between the guard and here means `reset()` already cleared
        // this axis to honour "born healthy", and a stale apply would write the
        // absence straight back into the NEW engagement.
        //
        // The price is real and worth stating: when the capability is still gone, the
        // key that would have shown a native HUD is swallowed and mute instead, while
        // the fresh apply re-learns. It is bought for the case that matters — a flip
        // is usually a lock/unlock, which is exactly when hardware comes back, and a
        // stale mark there hands away a key the app could now apply.
        //
        // DECLARED GAP: this guard is not pinned, and a test that pretended to pin it
        // was written and removed rather than kept. The window needs a stale apply to
        // resume AFTER an engage flip, and nothing observable marks that moment — the
        // absent set has no test-visible snapshot, and a `.noOp` fires no callback, so
        // every probe either presses too early (both behaviours agree) or retries
        // until the re-check has healed the difference away. Closing it honestly means
        // giving the decider a snapshot the way it already exposes `suspendedDomains`;
        // until someone wants that API for a second reason, the mutation that removes
        // this line survives the suite, and saying so here is worth more than a green
        // test that proves nothing.
        guard generation == self.generation, isEngaged else { return }
        guard decider.noteAbsentCapability(capability) else { return }
        logger.notice("no \(String(describing: capability), privacy: .public) control on this route — that key goes to the system until one answers")
    }

    /// What an apply actually did, which the success path must distinguish. A
    /// no-op wrote nothing, so it is proof of nothing: letting it share the
    /// verified branch cleared the write-health axis and dropped a channel's menu
    /// warning without a single write — one press on an output that lost its
    /// volume control was enough to wipe five episodes of evidence.
    private enum ApplyOutcome {
        /// A write landed and the read-back proved it moved.
        case verified
        /// The channel reports no such capability; nothing was written.
        case noOp
    }

    private func applyVerified(_ key: MediaKey, fine: Bool, generation: Int) async {
        guard generation == self.generation, isEngaged else { return }
        let domain = OSDSuppressionDomain(key)
        // A domain suspended after this apply was enqueued: no-op. The queued
        // key belongs to the pre-suspension world; the probe loop owns recovery.
        guard !decider.isSuspended(domain) else { return }
        do {
            let outcome = try await apply(key, fine: fine, generation: generation)
            // Re-check: the apply awaited, and a disengage may have landed. A
            // verified apply is the only proof the write path is alive: it clears
            // the write-flap axis and any menu warning a dead write had raised —
            // genuine recovery the read-only probe could never prove. A no-op
            // wrote nothing, so it earns neither that nor the HUD poke.
            if generation == self.generation, case .verified = outcome {
                confirmWriteHealthy(domain)
                onApplied?(key)
            }
        } catch {
            suspend(domain, after: key, error: error, generation: generation)
        }
    }

    private func apply(_ key: MediaKey, fine: Bool, generation: Int) async throws -> ApplyOutcome {
        switch key {
        case .mute:
            return try await applyMute(generation: generation)
        case .volumeUp, .volumeDown:
            return try await applyVolumeStep(key, fine: fine, generation: generation)
        case .screenBrightnessUp, .screenBrightnessDown:
            // Inline on purpose: DisplayServices answers availability from two dlsym
            // results resolved once at init, so it cannot block — and, being fixed
            // for the process, an absence here is one the re-check can never undo.
            // Its keyboard sibling below is a different animal and gets different
            // treatment; that divergence is the reason both are commented.
            guard screen.isAvailable() else { noteAbsent(.screenBrightness, generation: generation); return .noOp }
            try await step(screen, key: key, fine: fine)
            return .verified
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            // Raced like the volume guards: CoreBrightness answers this by
            // enumerating the backlight IDs over the private client's connection —
            // IPC, not a nil-check — and it is re-asked per call precisely because a
            // cold boot can answer "no keyboard" before the service is up. Inline,
            // this blocked the MainActor once per backlight key.
            guard try await readWithDeadline({ [keyboard] in keyboard.isAvailable() }) else {
                noteAbsent(.keyboardBrightness, generation: generation); return .noOp
            }
            try await step(keyboard, key: key, fine: fine)
            return .verified
        }
    }

    private func applyMute(generation: Int) async throws -> ApplyOutcome {
        // No mute control on this output (plenty of USB/HDMI devices): nothing to
        // write, never a failure. Reads are deadline-raced — supportsMute and
        // readMuted are Core Audio IPC that can stall.
        guard try await readWithDeadline({ [volume] in volume.supportsMute() }) else {
            noteAbsent(.mute, generation: generation); return .noOp
        }
        guard let muted = try await readWithDeadline({ [volume] in volume.readMuted() }) else {
            throw ApplyFailure.currentValueUnreadable
        }
        try await withDeadline { [volume] in try await volume.setMuted(!muted) }
        // Nil read-back is a read failure, not a dead write — the same line the
        // pre-read draws (see `step`).
        guard let after = try await readWithDeadline({ [volume] in volume.readMuted() }) else {
            throw ApplyFailure.currentValueUnreadable
        }
        guard after == !muted else { throw ApplyFailure.verificationFailed }
        return .verified
    }

    private func applyVolumeStep(_ key: MediaKey, fine: Bool, generation: Int) async throws -> ApplyOutcome {
        // The availability/mute guards are Core Audio IPC (defaultOutputDeviceID)
        // that can stall, so they race the deadline like the reads.
        guard try await readWithDeadline({ [volume] in volume.isAvailable() }) else {
            noteAbsent(.volumeLevel, generation: generation); return .noOp
        }
        // Volume-up unmutes first, like the native handler — otherwise the key
        // "does nothing" audible while the device stays muted. Verified like any
        // write: a dead mute plane must suspend the domain, not leave the user
        // pressing a silent volume key.
        if key == .volumeUp {
            // Unfolded from a condition chain because this reading is an ANSWER to
            // record in BOTH directions, not just a branch to skip. It asks the same
            // fact `applyMute` guards on and is the more frequent of the two by a
            // wide margin — volume-up is pressed far more than mute — so learning
            // only in `applyMute` would leave the mute key swallowed through every
            // volume press that had already proved the plane missing, and forgetting
            // only there would leave it handed to the system through every volume
            // press that had already proved it back. Clearing here is safe for the
            // same reason the re-check's clear is: only a positive answer from the
            // channel itself ever removes a mark.
            if try await readWithDeadline({ [volume] in volume.supportsMute() }) {
                decider.clearAbsentCapability(.mute)
                // A nil mute read is a read failure, not "not muted" — the same
                // line `applyMute` draws. Skipping the unmute on it left the key
                // consumed and the bar rising over a Mac that stayed muted, with
                // no failure axis touched. Nil throws so the apply fails and the
                // domain follows the ordinary suspension rules; only a real
                // `false` (read fine, not muted) skips the unmute.
                guard let muted = try await readWithDeadline({ [volume] in volume.readMuted() }) else {
                    throw ApplyFailure.currentValueUnreadable
                }
                if muted {
                    try await withDeadline { [volume] in try await volume.setMuted(false) }
                    guard let stillMuted = try await readWithDeadline({ [volume] in volume.readMuted() }) else {
                        throw ApplyFailure.currentValueUnreadable
                    }
                    guard !stillMuted else { throw ApplyFailure.verificationFailed }
                }
            } else {
                noteAbsent(.mute, generation: generation)
            }
        }
        try await step(volume, key: key, fine: fine)
        return .verified
    }

    private func step(_ channel: any OSDChannel, key: MediaKey, fine: Bool) async throws {
        // Pre-read and read-back are deadline-raced: a blocked C read on the
        // MainActor would freeze the app and wedge the queue.
        guard let before = try await readWithDeadline({ [channel] in channel.read() }),
              let target = MediaKeyStepper.next(from: before, key: key, fine: fine) else {
            throw ApplyFailure.currentValueUnreadable
        }
        try await withDeadline { [channel] in try await channel.apply(target) }
        // A read-back that comes back nil is a READ failure and says nothing
        // about the write, so it is unfolded here instead of being handed to
        // `verified` (which answers false for a nil `after`). Folding it in
        // billed a dead read to the write-health axis — the axis whose own
        // contract excludes read-side failures — and after five episodes the
        // menu told the user Crema could not apply a change whose write was
        // fine. The pre-read above already draws this line; the read-back has
        // the same claim to it.
        guard let after = try await readWithDeadline({ [channel] in channel.read() }) else {
            throw ApplyFailure.currentValueUnreadable
        }
        var settled = after
        // One more look, and only when the reading is AMBIGUOUS rather than
        // wrong. Nothing moved is the signature of a write the HAL took and has
        // not published yet, which Apple documents as the general case
        // (`mayBeAsynchronous`) — so the healthy path never pays for this, and
        // the path that does was previously suspending the domain and telling
        // the user Crema could not change a volume it had just changed.
        if !OSDApplyVerification.verified(before: before, target: target, after: settled),
           OSDApplyVerification.mayBeAsynchronous(before: before, target: target, after: settled) {
            guard let second = try await readWithDeadline({ [channel] in channel.read() }) else {
                throw ApplyFailure.currentValueUnreadable
            }
            settled = second
        }
        guard OSDApplyVerification.verified(before: before, target: target, after: settled) else {
            throw ApplyFailure.verificationFailed
        }
    }

    /// Bounds a write by the apply deadline (mechanism in OSDApplyDeadline): a
    /// hung actuator (coreaudiod stall, Bluetooth output dropping mid-write) that
    /// never returns would otherwise strand the apply chain while keys keep being
    /// consumed. Maps the timeout onto the domain-suspension path.
    private func withDeadline(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        do {
            try await raceWriteDeadline(seconds: applyDeadline, clock: clock, operation)
        } catch is DeadlineExceeded {
            logger.error("apply exceeded the \(self.applyDeadline, privacy: .public)s deadline — abandoning the hung write, suspending the domain")
            throw ApplyFailure.writeTimedOut
        }
    }

    /// The read-side sibling of the write deadline: bounds a blocking C read by
    /// the same deadline so a stalled read never freezes the MainActor and wedges
    /// the queue. Reads sleep on `readClock`, apart from the probe backoff on
    /// `clock`. (docs/DECISIONS.md: read-deadline-pool-rule)
    private func readWithDeadline<T: Sendable>(_ read: @escaping @Sendable () -> T) async throws -> T {
        do {
            return try await raceReadDeadline(seconds: applyDeadline, clock: readClock, read)
        } catch is DeadlineExceeded {
            // Deliberately does not name a consequence: the apply path maps this
            // onto a domain suspension, while the capability re-check is clear-only
            // and just leaves the absence standing. Naming one would lie to whoever
            // reads the other in Console.
            logger.error("a channel read exceeded the \(self.applyDeadline, privacy: .public)s deadline — abandoning the hung read")
            throw ApplyFailure.readTimedOut
        }
    }

    // MARK: - Per-domain suspension and recovery

    private func suspend(_ domain: OSDSuppressionDomain, after key: MediaKey, error: Error, generation: Int) {
        // A burst of failures queues several entries for the same domain; only
        // the first one that still matches the generation suspends and starts
        // the probe. Later ones hit the applyVerified suspension guard.
        guard generation == self.generation, isEngaged else { return }
        guard !decider.isSuspended(domain) else { return }
        decider.suspend(domain)
        let name = String(describing: domain)
        logger.notice("\(name, privacy: .public) apply failed (\(error, privacy: .public)) — suspending it, native OSD restored")
        // Write-health escalation axis (docs/DECISIONS.md: write-health-axis): a
        // read-OK/write-dead episode the read-only probe will optimistically
        // re-engage flaps forever, so count those episodes here — reset only by a
        // verified apply — to surface a persistently un-appliable channel in the
        // menu. Only the write-side signatures feed it (a verified write that never
        // moved, a hung write); a read-side failure is the probe's own axis, and
        // counting it here would both double-count it and mislabel a read stall as
        // a dead write. Never writes the pref (docs/DECISIONS.md: pref-sacred);
        // only feeds the same long-suspended set the probe axis does.
        if Self.isWriteHealthFailure(error) {
            let flaps = (unconfirmedApplyFailures[domain] ?? 0) + 1
            unconfirmedApplyFailures[domain] = flaps
            if flaps >= Self.writeHealthEscalationThreshold, !longSuspendedDomains.contains(domain) {
                longSuspendedDomains.insert(domain)
                onSuspensionStateChange?()
                logger.notice("\(name, privacy: .public) apply keeps failing with the read healthy — surfacing in the menu (dead write)")
            }
        }
        startProbe(domain, generation: generation)
    }

    /// A verified apply proved the write path alive: clear the flap axis and, if
    /// a write-dead channel had escalated, drop its menu warning. The read-only
    /// probe can never do this — only a real, verified write can.
    private func confirmWriteHealthy(_ domain: OSDSuppressionDomain) {
        guard unconfirmedApplyFailures.removeValue(forKey: domain) != nil else { return }
        if longSuspendedDomains.remove(domain) != nil {
            onSuspensionStateChange?()
        }
    }

    private func startProbe(_ domain: OSDSuppressionDomain, generation: Int) {
        let probe = probes[domain] ?? DomainProbe()
        probes[domain] = probe
        probe.task?.cancel()
        probe.task = Task { [weak self] in
            await self?.runProbeLoop(domain, generation: generation)
        }
    }

    private func runProbeLoop(_ domain: OSDSuppressionDomain, generation: Int) async {
        while !Task.isCancelled {
            // Wait phase (may suspend on the clock). Scoped so its `probe`
            // binding does not clash with the post-await re-fetch.
            let immediate: Bool
            let delay: Double
            do {
                guard generation == self.generation, let probe = probes[domain] else { return }
                immediate = probe.probeImmediately
                probe.probeImmediately = false
                delay = Self.probeBackoff(attempt: probe.backoffAttempt)
            }
            if !immediate {
                do { try await clock.sleep(for: delay) } catch { return }   // cancelled: kick or disengage
            }
            // Probe phase. Re-fetch: a disengage/re-engage may have cleared the
            // state across the backoff await.
            guard generation == self.generation,
                  let probe = probes[domain],
                  decider.isSuspended(domain) else { return }
            if !immediate { probe.backoffAttempt += 1 }
            let outcome = await probeOutcome(domain)
            // probeOutcome awaits (its reads race the read deadline); a
            // disengage/re-engage across it invalidates this probe. Re-validate
            // before mutating suspension state — a stale probe must not re-arm a
            // menu warning a disengage just cleared.
            guard generation == self.generation,
                  probes[domain] === probe,
                  decider.isSuspended(domain) else { return }
            switch outcome {
            case .recovered:
                reengage(domain, generation: generation)
                return
            case .failedChannelPresent:
                // Only scheduled backoff probes count toward escalation. A
                // key-kicked (immediate) probe skips the backoff advance above
                // and must skip the counter too: otherwise every autorepeat/
                // press on a present-but-dead channel kicks a probe, driving the
                // counter to the threshold in a fraction of a second and
                // surfacing the long-suspended menu warning far below the ~31 s
                // of accumulated backoff this window is meant to represent.
                if !immediate {
                    probe.channelPresentFailures += 1
                    if probe.channelPresentFailures >= Self.escalationThreshold, !probe.longSuspended {
                        probe.longSuspended = true
                        longSuspendedDomains.insert(domain)
                        onSuspensionStateChange?()
                        let name = String(describing: domain)
                        logger.notice("\(name, privacy: .public) unrecoverable across \(Self.escalationThreshold) probes — surfacing in the menu")
                    }
                }
            case .failedChannelAbsent:
                // A device transition (no output device) never escalates: there
                // is no channel to blame, and the key already falls through to
                // the native OSD while suspended. Keep probing quietly.
                break
            }
        }
    }

    private enum ProbeOutcome { case recovered, failedChannelPresent, failedChannelAbsent }

    /// A recovery probe: a cheap read (plus, for volume, a present-device
    /// check), never a write — re-driving a write here would flip the value
    /// under the user. `isAvailable()` separates a genuinely absent channel (a
    /// disconnected output — a device transition that must never escalate) from
    /// a present channel that still cannot be read.
    private func probeOutcome(_ domain: OSDSuppressionDomain) async -> ProbeOutcome {
        let channel = channel(for: domain)
        do {
            switch domain {
            case .volume:
                // Volume isAvailable() is Core Audio IPC and can stall, so it is
                // deadline-raced along with the read.
                let present = try await readWithDeadline { [channel] in channel.isAvailable() }
                guard present else { return .failedChannelAbsent }
                let value = try await readWithDeadline { [channel] in channel.read() }
                return value != nil ? .recovered : .failedChannelPresent
            case .screenBrightness:
                // DisplayServices availability is two dlsym results resolved once at
                // init, so it cannot block; only the read can hang and is raced.
                let present = channel.isAvailable()
                let value = try await readWithDeadline { [channel] in channel.read() }
                if value != nil { return .recovered }
                return present ? .failedChannelPresent : .failedChannelAbsent
            case .keyboardBrightness:
                // Unlike its screen sibling, CoreBrightness availability enumerates
                // the backlight IDs over the private client's connection — IPC that
                // can stall — so it is raced like the read beside it. Inline, it
                // blocked the MainActor once per backoff cycle of this loop.
                let present = try await readWithDeadline { [channel] in channel.isAvailable() }
                let value = try await readWithDeadline { [channel] in channel.read() }
                if value != nil { return .recovered }
                return present ? .failedChannelPresent : .failedChannelAbsent
            }
        } catch {
            // A probe read hung past the deadline: treat it as a present-but-
            // unreadable channel (a persistent stall) so it escalates like any
            // unrecoverable domain, never freezing the probe loop on the read.
            return .failedChannelPresent
        }
    }

    private func channel(for domain: OSDSuppressionDomain) -> any OSDChannel {
        switch domain {
        case .volume: volume
        case .screenBrightness: screen
        case .keyboardBrightness: keyboard
        }
    }

    private func reengage(_ domain: OSDSuppressionDomain, generation: Int) {
        guard generation == self.generation, decider.isSuspended(domain) else { return }
        decider.resume(domain)
        probes[domain]?.task?.cancel()
        probes[domain] = nil
        // A read-only probe recovering proves only the READ path. If the domain
        // escalated because its WRITE keeps failing (flap axis at the threshold),
        // keep the menu warning until a verified apply proves the write alive —
        // clearing it on this optimistic re-engage would flicker it off every
        // cycle. A read-driven escalation (flap axis below threshold) recovers
        // genuinely on this read, so its warning clears as before.
        let writeStillUnconfirmed = (unconfirmedApplyFailures[domain] ?? 0) >= Self.writeHealthEscalationThreshold
        if !writeStillUnconfirmed, longSuspendedDomains.remove(domain) != nil {
            onSuspensionStateChange?()
        }
        logger.info("\(String(describing: domain), privacy: .public) recovered on a probe — re-engaged silently")
    }

    /// Interrupts the parked backoff so the next probe runs now. Coalesced by
    /// the `probeImmediately` flag: a held key autorepeating fires one kick per
    /// probe cycle, not one per repeat.
    private func kickProbe(_ domain: OSDSuppressionDomain) {
        guard let probe = probes[domain], decider.isSuspended(domain) else { return }
        guard !probe.probeImmediately else { return }
        probe.probeImmediately = true
        startProbe(domain, generation: generation)
    }

    func retrySuspendedNow() {
        for domain in OSDSuppressionDomain.allCases {
            if decider.isSuspended(domain) {
                // Still suspended: kick the read-only recovery probe ahead of its
                // backoff, exactly as an active user's key press would.
                //
                // The same click also consents to re-testing the WRITE, so the
                // write-health count goes with it. It has to, because the fifth flap
                // of a read-alive/write-dead channel suspends and escalates in the
                // SAME step: a click inside that window would otherwise reach only
                // this branch, the probe would re-engage on the read, and `reengage`
                // would find the count still standing and keep the menu warning up —
                // the button doing visibly nothing, which is the whole complaint.
                //
                // Only the COUNT, never the menu set, and this is the line that makes
                // the obvious fix wrong: turning the `else if` into a second `if`
                // would let `clearWriteHealthLatch` drop the warning of a domain
                // escalated by the PROBE axis, which is still suspended and still
                // dead — and that probe's own `longSuspended` flag never raises it a
                // second time, so the channel would go dark permanently. Measured.
                unconfirmedApplyFailures[domain] = nil
                kickProbe(domain)
            } else if longSuspendedDomains.contains(domain) {
                // Long-suspended in the menu, yet no longer suspended: the
                // read-only probe re-engaged the domain but its warning is latched
                // pending a verified apply (a write-dead/hung channel). There is no
                // live probe to kick and the domain is already suppressing again,
                // so the kick branch above cannot reach it — that is exactly why
                // the menu button was a no-op here. An explicit user retry clears
                // the latch and lets the next real apply re-prove the write: if it
                // is still dead it re-escalates on its own over the next flaps, but
                // the button now does something and a warning left stale by a
                // silently-healed write (verified apply never triggered because the
                // user stopped pressing) is dismissible.
                clearWriteHealthLatch(domain)
            }
        }
    }

    /// Drops the write-health flap axis and any latched menu warning for a domain
    /// WITHOUT a verified apply — the one path allowed to do so, since it is
    /// driven by the explicit user retry, which consents to re-testing the write
    /// through the normal apply path. (The passive clearer is `confirmWriteHealthy`,
    /// which requires a real verified apply.)
    private func clearWriteHealthLatch(_ domain: OSDSuppressionDomain) {
        unconfirmedApplyFailures[domain] = nil
        if longSuspendedDomains.remove(domain) != nil {
            onSuspensionStateChange?()
        }
    }

    private func cancelAllProbes() {
        for probe in probes.values { probe.task?.cancel() }
        probes.removeAll()
    }
}
