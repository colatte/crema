import AppKit
import CoreGraphics
import Foundation
import os

/// Real media-key source: a CGEventTap on NX_SYSDEFINED events.
///
/// Observation by default: with no consumer set, the callback returns every
/// event untouched and the system processes every key normally (native OSD
/// included). Setting a consumer (native-OSD suppression) routes every owned
/// key — both phases — through the consumer, which decides per event whether
/// to swallow it (and, on a key-down, becomes responsible for applying the
/// change). The consumer can pass a key straight through (its Bool returns
/// false), which is how one suspended domain falls back to the native OSD
/// while the others stay suppressed. The tap is created as `.defaultTap` even
/// in observation mode: a listen-only tap can never swallow, and swapping tap
/// types at toggle time would add an install/teardown failure mode.
///
/// Requires Accessibility. Without it, the source reports unavailable and the
/// app keeps running; a polling task keeps re-checking and installs the tap
/// the moment permission lands, so granting does not require a relaunch.
final class CGEventTapMediaKeySource: MediaKeySource, MediaKeyConsuming, @unchecked Sendable {
    let updates: AsyncStream<MediaKey>

    private let continuation: AsyncStream<MediaKey>.Continuation
    private let permission: any AccessibilityPermission
    private let clock: any SleepClock
    private let pollInterval: Double
    private let tapOps: any EventTapOperating
    private let lock = NSLock()
    /// The installed tap's opaque token (nil = not installed). The concrete
    /// port/run-loop-source live inside the token, owned by `tapOps`.
    private var tap: AnyObject?
    private var pollTask: Task<Void, Never>?
    private var consumer: Consumer?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "MediaKeys"
    )

    init(
        permission: any AccessibilityPermission,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2,
        tapOps: any EventTapOperating = LiveEventTapOperating()
    ) {
        // Nothing consumes this stream until the HUD wiring lands;
        // newest-bounded buffering keeps unconsumed key presses from piling up.
        var continuation: AsyncStream<MediaKey>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation = $0 }
        self.continuation = continuation
        self.permission = permission
        self.clock = clock
        self.pollInterval = pollInterval
        self.tapOps = tapOps

        // Self-healing lifecycle: the loop never exits. Grant → install;
        // revoke → tear down (macOS kills delivery anyway; we make the state
        // honest); re-grant → reinstall. The stream stays open through a
        // revocation because the condition is recoverable in-process —
        // `finish` is reserved for the source's own end of life (deinit).
        //
        // Beyond install/teardown, the poll health-checks an installed tap. Two
        // failure modes the system inflicts behind our back, with no delivered
        // callback: (1) it disables a consuming tap (a re-enable inside the lock
        // screen's secure-input context can be silently reverted) — the port stays
        // valid and a re-enable revives it; (2) it invalidates the mach port
        // outright — dead permanently, no re-enable can bring it back, so the
        // health-check reinstalls from scratch. Left unhandled either way, keys
        // reach the system and the native OSD comes back alongside ours.
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.permission.isGranted() {
                    if self.installTapIfAuthorized() {
                        self.healTapIfNeeded(reason: "poll")
                    }
                } else {
                    self.tearDownTapIfInstalled()
                }
                try? await self.clock.sleep(for: self.pollInterval)
            }
        }
    }

    deinit {
        pollTask?.cancel()
        lock.lock()
        if let tap {
            tapOps.uninstall(tap)
        }
        lock.unlock()
        continuation.finish()
    }

    /// Availability is permission-driven; the tap itself installs (or retries)
    /// on the polling path. Without permission: degraded, never a crash.
    func isAvailable() async -> Bool {
        permission.isGranted()
    }

    /// Nil restores pure observation (the system sees every key again) — the
    /// reversibility story of key-based suppression is exactly this line.
    ///
    /// This is also the re-engage seam after an unlock: the suppressor sets its
    /// consumer here, so this is the moment to physically revalidate the tap.
    /// If the lock screen's secure-input context silently disabled it, waiting
    /// for the 2 s poll would leave a window where keys reach the system (double
    /// HUD); healing now restores a working tap instantly. A merely-disabled port
    /// is re-enabled in place; an invalidated port is reinstalled from scratch —
    /// and because the consumer is already stored above, the fresh port adopts it,
    /// so re-engage never drops suppression.
    func setConsumer(_ consumer: Consumer?) {
        lock.lock()
        self.consumer = consumer
        healTapLocked(reason: "re-engage")
        lock.unlock()
    }

    // MARK: - Tap installation (border)

    /// Returns true once the tap is installed. Acquires the lock; see
    /// `installTapIfAuthorizedLocked`.
    private func installTapIfAuthorized() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return installTapIfAuthorizedLocked()
    }

    /// Creates the tap if none is installed. Must be called with `lock` held.
    /// Never touches the CGEvent API while the permission is missing. The
    /// callback resolves the source from `userInfo` and reads `self.consumer` on
    /// every event, so a reinstall from `healTapLocked` preserves suppression by
    /// construction — the fresh port points back at the same source and its
    /// unchanged consumer.
    private func installTapIfAuthorizedLocked() -> Bool {
        guard tap == nil else { return true }
        guard permission.isGranted() else { return false }

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let source = Unmanaged<CGEventTapMediaKeySource>.fromOpaque(userInfo).takeUnretainedValue()
            // Nil swallows the event (suppression); otherwise it continues to
            // every other consumer untouched.
            return source.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }

        let mask = CGEventMask(1 << MediaKeyTranslation.systemDefinedEventType)
        guard let newTap = tapOps.install(
            mask: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("event tap creation failed despite permission; will retry")
            return false
        }

        tap = newTap
        logger.info("media-key tap installed")
        return true
    }

    private func tearDownTapIfInstalled() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return }
        tapOps.uninstall(tap)
        self.tap = nil
        logger.info("media-key tap removed (permission revoked); will reinstall on re-grant")
    }

    /// Health-check wrapper for the poll path. Acquires the lock; see
    /// `healTapLocked`.
    private func healTapIfNeeded(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        healTapLocked(reason: reason)
    }

    /// Health-check for a tap that went bad behind our back. Must be called with
    /// `lock` held. Two distinct failure modes, two responses:
    ///
    /// - Port invalidated (`CFMachPortIsValid` false): the tap is permanently
    ///   dead — no `setEnabled` revives an invalid port. Uninstall and reinstall
    ///   from scratch; the fresh port's callback reads `self.consumer`
    ///   dynamically, so suppression survives by construction. Validity is
    ///   definitive (unlike a transient disable), so there is deliberately no
    ///   counter/backoff here — one detection, one reinstall.
    /// - Port valid but disabled: a re-enable restores it (the J1 secure-input /
    ///   timeout path), keeping the same port and its consumer wiring intact.
    private func healTapLocked(reason: String) {
        guard let tap else { return }
        if !tapOps.isValid(tap) {
            tapOps.uninstall(tap)
            self.tap = nil
            if installTapIfAuthorizedLocked() {
                logger.notice("media-key tap port invalidated (\(reason, privacy: .public)); reinstalled")
            } else {
                logger.error("media-key tap port invalidated (\(reason, privacy: .public)); reinstall deferred to poll")
            }
            return
        }
        reviveTapIfDisabledLocked(reason: reason)
    }

    /// Re-enables an installed-but-disabled tap. Must be called with `lock`
    /// held. Only re-enables; never reinstalls — the same port keeps its
    /// callback wiring (and thus the consumer) intact.
    private func reviveTapIfDisabledLocked(reason: String) {
        guard let tap, !tapOps.isEnabled(tap) else { return }
        tapOps.setEnabled(tap, true)
        logger.debug("media-key tap was installed but disabled (\(reason, privacy: .public)); re-enabled")
    }

    /// Returns whether the event must be swallowed (suppression active and the
    /// key is ours — both phases, see MediaKeyTranslation.ownedKey).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables taps it considers slow, or across secure-input
        // transitions; re-enable and move on. This handles the disables that do
        // arrive as a callback — the poll and re-engage paths cover the ones
        // the system applies silently.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = self.tap
            lock.unlock()
            if let tap { tapOps.setEnabled(tap, true) }
            logger.debug("media-key tap disabled by system (type \(type.rawValue, privacy: .public)); re-enabled in callback")
            return false
        }

        guard type.rawValue == MediaKeyTranslation.systemDefinedEventType,
              let systemEvent = NSEvent(cgEvent: event),
              systemEvent.subtype.rawValue == MediaKeyTranslation.auxiliaryControlSubtype
        else { return false }

        let data1 = systemEvent.data1

        // The stream observes key-downs/repeats regardless of suppression —
        // it is what pokes the brightness sources into emitting the HUD.
        if let key = MediaKeyTranslation.mediaKey(fromData1: data1) {
            logger.debug("media key observed: \(String(describing: key), privacy: .public)")
            continuation.yield(key)
        }

        guard let ownedKey = MediaKeyTranslation.ownedKey(ignoringPhaseFromData1: data1) else { return false }
        lock.lock()
        let consumer = self.consumer
        lock.unlock()
        guard let consumer else { return false }

        // The consumer decides per phase whether to swallow. `mediaKey(fromData1:)`
        // is the down-only decode (nil on key-up), so its non-nil result is the
        // key-down/repeat signal; the phase-blind `ownedKey` carries the key on
        // both phases. Fine-step only rides the down (a key-up applies nothing);
        // the consumer keeps the up consistent with the down it committed to.
        let isDown = MediaKeyTranslation.mediaKey(fromData1: data1) != nil
        let modifiers = systemEvent.modifierFlags
        let fine = isDown && modifiers.contains(.option) && modifiers.contains(.shift)
        return consumer(ownedKey, fine, isDown)
    }
}
