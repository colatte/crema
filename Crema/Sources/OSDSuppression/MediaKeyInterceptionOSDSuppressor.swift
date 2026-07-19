import Foundation
import os

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
///   on any single-channel failure (A1); no failure path writes the pref now.
/// - Applies race a deadline on an unstructured background task: a hung
///   actuator (a coreaudiod stall, a Bluetooth output dropping mid-write)
///   that never returns — not even to cancellation — would otherwise strand
///   the apply chain while keys keep being consumed. A structured child (task
///   group / async let) is joined at scope exit, so the deadline could never
///   return while the write hangs; running the write unstructured lets the
///   timeout return and suspend the domain while the write finishes orphaned.
///   Residual: a write that lands long after the deadline moves the value one
///   step (the consumed press's own intent) with no HUD — bounded to that
///   single press, because the domain is suspended and the queued keys fall
///   through the suspension guard rather than starting new writes.
/// - An absent capability is not a failure: outputs without a volume/mute
///   control and Macs without a keyboard backlight no-op (as the native
///   handler does) instead of suspending the domain on ordinary hardware.
@MainActor
final class MediaKeyInterceptionOSDSuppressor: NativeOSDSuppressor {
    /// Generous against slow-but-alive devices (Bluetooth volume writes can
    /// take hundreds of ms); a genuinely hung actuator still fails soon
    /// enough for the user to associate cause and effect.
    static let defaultApplyDeadline: Double = 2.0

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
    static let escalationThreshold = 5

    private static func probeBackoff(attempt: Int) -> Double {
        attempt < probeBackoffSchedule.count ? probeBackoffSchedule[attempt] : probeBackoffCap
    }

    private let keys: any MediaKeyConsuming
    private let volume: any OSDVolumeChannel
    private let screen: any OSDChannel
    private let keyboard: any OSDChannel
    private let clock: any SleepClock
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
        applyDeadline: Double = MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline
    ) {
        self.keys = keys
        self.volume = volume
        self.screen = screen
        self.keyboard = keyboard
        self.clock = clock
        self.applyDeadline = applyDeadline
    }

    func setEngaged(_ engaged: Bool) {
        guard engaged != isEngaged else { return }
        isEngaged = engaged
        generation += 1
        if engaged {
            // Fresh engagement: every domain healthy, no in-flight suspension.
            decider.reset()
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
        case currentValueUnreadable
        case verificationFailed
        case timedOut
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
        // like the native handler, never a failure.
        guard volume.supportsMute() else { passThroughUnavailable("mute"); return }
        guard let muted = volume.readMuted() else { throw ApplyFailure.currentValueUnreadable }
        try await withDeadline { [volume] in try await volume.setMuted(!muted) }
        guard volume.readMuted() == !muted else { throw ApplyFailure.verificationFailed }
    }

    private func applyVolumeStep(_ key: MediaKey, fine: Bool) async throws {
        guard volume.isAvailable() else { passThroughUnavailable("volume"); return }
        // Volume-up unmutes first, like the native handler — otherwise the key
        // "does nothing" audible while the device stays muted. Verified like any
        // write: a dead mute plane must suspend the domain, not leave the user
        // pressing a silent volume key.
        if key == .volumeUp, volume.supportsMute(), volume.readMuted() == true {
            try await withDeadline { [volume] in try await volume.setMuted(false) }
            guard volume.readMuted() == false else { throw ApplyFailure.verificationFailed }
        }
        try await step(volume, key: key, fine: fine)
    }

    private func step(_ channel: any OSDChannel, key: MediaKey, fine: Bool) async throws {
        guard let before = channel.read(),
              let target = MediaKeyStepper.next(from: before, key: key, fine: fine) else {
            throw ApplyFailure.currentValueUnreadable
        }
        try await withDeadline { [channel] in try await channel.apply(target) }
        guard OSDApplyVerification.verified(before: before, target: target, after: channel.read()) else {
            throw ApplyFailure.verificationFailed
        }
    }

    /// Races the write against the apply deadline so the deadline can always
    /// return — even against a write that never completes and never observes
    /// cancellation (a blocked synchronous C actuator call). The write runs on
    /// an unstructured, detached task: unstructured so this scope is never
    /// forced to join it (a task group or `async let` awaits every child at
    /// scope exit, which a hung write would block forever, defeating the very
    /// deadline this exists to enforce); detached so a blocked write parks on a
    /// background thread, not the MainActor. On timeout the write is cancelled
    /// (a no-op for a blocked C call, tidy-up for a cancellable one) and
    /// abandoned; the caller's failure path then suspends the domain.
    /// The deadline sleep always fires, so the continuation is resumed exactly
    /// once whatever the write does.
    private func withDeadline(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let race = DeadlineRace()
        let write = Task.detached {
            do {
                try await operation()
                race.finish(.success(()))
            } catch {
                race.finish(.failure(error))
            }
        }
        let deadline = Task.detached { [clock, applyDeadline] in
            do {
                try await clock.sleep(for: applyDeadline)
                race.finish(.failure(ApplyFailure.timedOut))
            } catch {
                // The write won the race and this sleep was cancelled.
            }
        }
        do {
            try await withCheckedThrowingContinuation { race.begin($0) }
            deadline.cancel()
        } catch {
            write.cancel()
            deadline.cancel()
            if case ApplyFailure.timedOut = error {
                logger.error("apply exceeded the \(self.applyDeadline, privacy: .public)s deadline — abandoning the hung write, suspending the domain")
            }
            throw error
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
        startProbe(domain, generation: generation)
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
            // Probe phase (synchronous). Re-fetch: a disengage/re-engage may
            // have cleared the state across the await.
            guard generation == self.generation,
                  let probe = probes[domain],
                  decider.isSuspended(domain) else { return }
            if !immediate { probe.backoffAttempt += 1 }
            switch probeOutcome(domain) {
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
    private func probeOutcome(_ domain: OSDSuppressionDomain) -> ProbeOutcome {
        let channel = channel(for: domain)
        let present = channel.isAvailable()
        let recovered: Bool
        switch domain {
        case .volume:
            recovered = present && channel.read() != nil
        case .screenBrightness, .keyboardBrightness:
            recovered = channel.read() != nil
        }
        if recovered { return .recovered }
        return present ? .failedChannelPresent : .failedChannelAbsent
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
        if longSuspendedDomains.remove(domain) != nil {
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
        for domain in OSDSuppressionDomain.allCases where decider.isSuspended(domain) {
            kickProbe(domain)
        }
    }

    private func cancelAllProbes() {
        for probe in probes.values { probe.task?.cancel() }
        probes.removeAll()
    }
}

/// Single-resume guard for the write/deadline race in withDeadline. The
/// abandoned write can land on any thread, so the guard is lock-based rather
/// than MainActor-bound; whichever racer finishes first resumes the
/// continuation and the rest no-op. If a racer finishes before begin installs
/// the continuation, the first result is stashed and delivered on begin — so
/// the continuation is resumed exactly once, never lost, never twice.
private final class DeadlineRace: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var pendingResult: Result<Void, Error>?
    private var resumed = false

    func begin(_ continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        if let result = pendingResult {
            resumed = true
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func finish(_ result: Result<Void, Error>) {
        lock.lock()
        guard !resumed else { lock.unlock(); return }
        if let continuation {
            resumed = true
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else if pendingResult == nil {
            pendingResult = result
            lock.unlock()
        } else {
            lock.unlock()
        }
    }
}
