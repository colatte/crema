import Foundation
import os

// One cohesive class: apply + verify + per-domain suspension + the two recovery
// axes (read-driven probe, write-health flap). Its collaborators (DomainProbe,
// SuppressionDecider, the deadline machinery) are already split out; the rest is
// tightly coupled and large.
// swiftlint:disable file_length

/// Suppresses the native volume/brightness OSD by consuming the media keys:
/// the system never sees the key, so it never shows its HUD, and the app
/// becomes the only applier (docs/osd-suppression-reference.md §3.1 — the
/// technique the ecosystem converged on for macOS 26, where the redesigned
/// OSD is rendered by ControlCenter and the old helper-suspension trick died;
/// §3.2 records why that alternative was rejected).
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
///   queue (the deadline covers the pre-read, read-back, mute-plane reads and the
///   volume capability guards; brightness guards stay inline as pure dlsym
///   nil-checks that never block; docs/DECISIONS.md: read-deadline-pool-rule).
///   On timeout the domain is suspended and the operation
///   abandoned; a late orphan is bounded and pure — a write moves the value one
///   step with no HUD (the consumed press's own intent), a read writes nothing —
///   because the domain is suspended and the queued keys fall through the
///   suspension guard rather than starting new work.
/// - An absent capability is not a failure: outputs without a volume/mute
///   control and Macs without a keyboard backlight no-op (as the native
///   handler does) instead of suspending the domain on ordinary hardware.
@MainActor
final class MediaKeyInterceptionOSDSuppressor: NativeOSDSuppressor {
    /// Generous against slow-but-alive devices (Bluetooth volume writes can
    /// take hundreds of ms); a genuinely hung actuator still fails soon
    /// enough for the user to associate cause and effect.
    nonisolated static let defaultApplyDeadline: Double = 2.0

    /// Recovery-probe backoff: 1, 2, 4, 8, 16 s, then 30 s forever. The first
    /// three cover the typical AirPods/output-swap window (<5 s), re-engaging
    /// in silence; the 30 s cap keeps the self-heal eternal and cheap.
    static let probeBackoffSchedule: [Double] = [1, 2, 4, 8, 16]
    static let probeBackoffCap: Double = 30

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

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "OSD"
    )

    init(
        keys: any MediaKeyConsuming,
        volume: any OSDVolumeChannel,
        screen: any OSDChannel,
        keyboard: any OSDChannel,
        clock: any SleepClock = ContinuousSleepClock(),
        readClock: any SleepClock = ContinuousSleepClock(),
        applyDeadline: Double = MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline
    ) {
        self.keys = keys
        self.volume = volume
        self.screen = screen
        self.keyboard = keyboard
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
                // the main actor.
                let swallow = self.decider.decide(key: key, isDown: isDown)
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

    private func handleConsumedDown(_ key: MediaKey, fine: Bool, swallowed: Bool, generation: Int) {
        guard generation == self.generation, isEngaged else { return }
        if swallowed {
            enqueue(key, fine: fine, generation: generation)
        } else {
            // A suspended domain's key passed to the system; an active user
            // pressing it is a cue to try recovering now, ahead of the backoff.
            kickProbe(OSDSuppressionDomain(key))
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

    /// A consumed key whose channel reports no capability is a no-op — as the
    /// native handler is on the same hardware (an HDMI/USB output without a
    /// volume or mute control, a Mac without a keyboard backlight, or the
    /// private symbols never resolving). It is not a failure and does not
    /// suspend, but the tap has already swallowed the key, so it must not be
    /// silent: a genuinely dead channel would otherwise eat the press with zero
    /// feedback and no trace. Logged once per channel so a degradation is
    /// diagnosable without spamming the log on every autorepeat.
    private var reportedUnavailable: Set<String> = []

    private func passThroughUnavailable(_ channel: String) {
        guard reportedUnavailable.insert(channel).inserted else { return }
        logger.notice("consumed a \(channel, privacy: .public) key but its channel is unavailable — no-op pass-through, like the native handler")
    }

    private func applyVerified(_ key: MediaKey, fine: Bool, generation: Int) async {
        guard generation == self.generation, isEngaged else { return }
        let domain = OSDSuppressionDomain(key)
        // A domain suspended after this apply was enqueued: no-op. The queued
        // key belongs to the pre-suspension world; the probe loop owns recovery.
        guard !decider.isSuspended(domain) else { return }
        do {
            try await apply(key, fine: fine)
            // Re-check: the apply awaited, and a disengage may have landed.
            if generation == self.generation {
                // A verified apply is the only proof the write path is alive: it
                // clears the write-flap axis and any menu warning a dead write had
                // raised — genuine recovery the read-only probe could never prove.
                confirmWriteHealthy(domain)
                onApplied?(key)
            }
        } catch {
            suspend(domain, after: key, error: error, generation: generation)
        }
    }

    private func apply(_ key: MediaKey, fine: Bool) async throws {
        switch key {
        case .mute:
            try await applyMute()
        case .volumeUp, .volumeDown:
            try await applyVolumeStep(key, fine: fine)
        case .screenBrightnessUp, .screenBrightnessDown:
            guard screen.isAvailable() else { passThroughUnavailable("screen brightness"); return }
            try await step(screen, key: key, fine: fine)
        case .keyboardBrightnessUp, .keyboardBrightnessDown:
            guard keyboard.isAvailable() else { passThroughUnavailable("keyboard brightness"); return }
            try await step(keyboard, key: key, fine: fine)
        }
    }

    private func applyMute() async throws {
        // No mute control on this output (plenty of USB/HDMI devices): no-op
        // like the native handler, never a failure. Reads are deadline-raced —
        // supportsMute/readMuted are Core Audio IPC that can stall.
        guard try await readWithDeadline({ [volume] in volume.supportsMute() }) else {
            passThroughUnavailable("mute"); return
        }
        guard let muted = try await readWithDeadline({ [volume] in volume.readMuted() }) else {
            throw ApplyFailure.currentValueUnreadable
        }
        try await withDeadline { [volume] in try await volume.setMuted(!muted) }
        guard try await readWithDeadline({ [volume] in volume.readMuted() }) == !muted else {
            throw ApplyFailure.verificationFailed
        }
    }

    private func applyVolumeStep(_ key: MediaKey, fine: Bool) async throws {
        // The availability/mute guards are Core Audio IPC (defaultOutputDeviceID)
        // that can stall, so they race the deadline like the reads.
        guard try await readWithDeadline({ [volume] in volume.isAvailable() }) else {
            passThroughUnavailable("volume"); return
        }
        // Volume-up unmutes first, like the native handler — otherwise the key
        // "does nothing" audible while the device stays muted. Verified like any
        // write: a dead mute plane must suspend the domain, not leave the user
        // pressing a silent volume key.
        if key == .volumeUp,
           try await readWithDeadline({ [volume] in volume.supportsMute() }),
           try await readWithDeadline({ [volume] in volume.readMuted() }) == true {
            try await withDeadline { [volume] in try await volume.setMuted(false) }
            guard try await readWithDeadline({ [volume] in volume.readMuted() }) == false else {
                throw ApplyFailure.verificationFailed
            }
        }
        try await step(volume, key: key, fine: fine)
    }

    private func step(_ channel: any OSDChannel, key: MediaKey, fine: Bool) async throws {
        // Pre-read and read-back are deadline-raced: a blocked C read on the
        // MainActor would freeze the app and wedge the queue.
        guard let before = try await readWithDeadline({ [channel] in channel.read() }),
              let target = MediaKeyStepper.next(from: before, key: key, fine: fine) else {
            throw ApplyFailure.currentValueUnreadable
        }
        try await withDeadline { [channel] in try await channel.apply(target) }
        let after = try await readWithDeadline { [channel] in channel.read() }
        guard OSDApplyVerification.verified(before: before, target: target, after: after) else {
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
            logger.error("a channel read exceeded the \(self.applyDeadline, privacy: .public)s deadline — abandoning the hung read, suspending the domain")
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
            case .screenBrightness, .keyboardBrightness:
                // Brightness isAvailable() is a pure dlsym nil-check (never
                // blocks); only the DisplayServices read can hang and is raced.
                let present = channel.isAvailable()
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
