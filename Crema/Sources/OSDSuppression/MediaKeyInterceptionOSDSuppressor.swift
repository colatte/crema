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
///   back; the first failure disengages and reports through
///   `onAutoDisengage` — a broken write path (a future macOS locking an
///   actuator) degrades to the native HUD instead of leaving the user
///   holding a dead volume key.
/// - Applies race a deadline on an unstructured background task: a hung
///   actuator (a coreaudiod stall, a Bluetooth output dropping mid-write)
///   that never returns — not even to cancellation — would otherwise strand
///   the apply chain while keys keep being consumed. A structured child (task
///   group / async let) is joined at scope exit, so the deadline could never
///   return while the write hangs; running the write unstructured lets the
///   timeout return and disengage while the write finishes orphaned. Residual:
///   a write that lands long after the deadline moves the value one step (the
///   consumed press's own intent) with no HUD — bounded to that single press,
///   because disengage stops further consumption and the queued keys fall
///   through the generation guard rather than starting new writes.
/// - An absent capability is not a failure: outputs without a volume/mute
///   control and Macs without a keyboard backlight no-op (as the native
///   handler does) instead of self-destructing the feature on ordinary
///   hardware.
@MainActor
final class MediaKeyInterceptionOSDSuppressor: NativeOSDSuppressor {
    /// Generous against slow-but-alive devices (Bluetooth volume writes can
    /// take hundreds of ms); a genuinely hung actuator still fails soon
    /// enough for the user to associate cause and effect.
    static let defaultApplyDeadline: Double = 2.0

    private let keys: any MediaKeyConsuming
    private let volume: any OSDVolumeChannel
    private let screen: any OSDChannel
    private let keyboard: any OSDChannel
    private let clock: any SleepClock
    private let applyDeadline: Double

    private(set) var isEngaged = false
    var onAutoDisengage: (@MainActor () -> Void)?
    /// Fired after each verified apply — AppCore pokes the matching
    /// brightness sampler so the app's HUD shows the post-apply value
    /// (Core Audio is event-driven and needs no poke; the media-key router's
    /// key-time poke still gives the HUD its instant appearance).
    var onApplied: (@MainActor (MediaKey) -> Void)?

    /// Applies run strictly in key order: an autorepeat burst over async
    /// applies would otherwise read the same base value twice and lose steps.
    private var pending: Task<Void, Never>?
    /// Bumped on every engage/disengage flip. Chain entries carry the
    /// generation they were enqueued under and no-op once it moves on — a
    /// bare isEngaged check would let a key consumed just before a disengage
    /// apply after a rapid re-engage.
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
            // The generation is baked into the consumer at install time: a
            // key consumed under this engagement hops to the main actor
            // carrying it, so a disengage/re-engage landing before the hop
            // cannot adopt the stale key into the new engagement.
            let installedGeneration = generation
            keys.setConsumer { [weak self] key, fine in
                Task { @MainActor in self?.enqueue(key, fine: fine, generation: installedGeneration) }
            }
            logger.info("native-OSD suppression engaged")
        } else {
            // Nil restores pure observation — the whole reversibility story.
            keys.setConsumer(nil)
            logger.info("native-OSD suppression disengaged")
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

    private func applyVerified(_ key: MediaKey, fine: Bool, generation: Int) async {
        guard generation == self.generation, isEngaged else { return }
        do {
            switch key {
            case .mute:
                // No mute control on this output (plenty of USB/HDMI devices):
                // no-op like the native handler, never a failure.
                guard volume.supportsMute() else { return }
                guard let muted = volume.readMuted() else { throw ApplyFailure.currentValueUnreadable }
                try await withDeadline { [volume] in try await volume.setMuted(!muted) }
                guard volume.readMuted() == !muted else { throw ApplyFailure.verificationFailed }
            case .volumeUp, .volumeDown:
                guard volume.isAvailable() else { return }
                // Volume-up unmutes first, like the native handler — otherwise
                // the key "does nothing" audible while the device stays muted.
                // Verified like any write: a dead mute plane must disengage,
                // not leave the user pressing a silent volume key.
                if key == .volumeUp, volume.supportsMute(), volume.readMuted() == true {
                    try await withDeadline { [volume] in try await volume.setMuted(false) }
                    guard volume.readMuted() == false else { throw ApplyFailure.verificationFailed }
                }
                try await step(volume, key: key, fine: fine)
            case .screenBrightnessUp, .screenBrightnessDown:
                guard screen.isAvailable() else { return }
                try await step(screen, key: key, fine: fine)
            case .keyboardBrightnessUp, .keyboardBrightnessDown:
                guard keyboard.isAvailable() else { return }
                try await step(keyboard, key: key, fine: fine)
            }
            // Re-check: the apply awaited, and a disengage may have landed.
            if generation == self.generation {
                onApplied?(key)
            }
        } catch {
            autoDisengage(after: key, error: error, generation: generation)
        }
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
    /// abandoned; the caller's failure path then restores the native behavior.
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
                logger.error("apply exceeded the \(self.applyDeadline, privacy: .public)s deadline — abandoning the hung write, disengaging")
            }
            throw error
        }
    }

    private func autoDisengage(after key: MediaKey, error: Error, generation: Int) {
        // A burst of failures queues several entries; only the first one that
        // still matches the generation disengages and reports — setEngaged
        // bumps it, so the rest fall through the applyVerified guard.
        guard generation == self.generation, isEngaged else { return }
        logger.error("consumed \(String(describing: key), privacy: .public) but failed to apply: \(error, privacy: .public) — disengaging, native HUD restored")
        setEngaged(false)
        onAutoDisengage?()
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
