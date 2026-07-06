import AppKit
import CoreGraphics
import Foundation
import os

/// Real media-key source: a CGEventTap on NX_SYSDEFINED events.
///
/// Observation by default: with no consumer set, the callback returns every
/// event untouched and the system processes every key normally (native OSD
/// included). Setting a consumer (native-OSD suppression) makes the
/// tap swallow the owned keys — both phases — and forward key-downs to the
/// consumer, which becomes responsible for applying the change. The tap is
/// created as `.defaultTap` even in observation mode: a listen-only tap can
/// never swallow, and swapping tap types at toggle time would add an
/// install/teardown failure mode.
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
    private let lock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTask: Task<Void, Never>?
    private var consumer: Consumer?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
        category: "MediaKeys"
    )

    init(
        permission: any AccessibilityPermission,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2
    ) {
        // Nothing consumes this stream until the HUD wiring lands;
        // newest-bounded buffering keeps unconsumed key presses from piling up.
        var continuation: AsyncStream<MediaKey>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation = $0 }
        self.continuation = continuation
        self.permission = permission
        self.clock = clock
        self.pollInterval = pollInterval

        // Self-healing lifecycle: the loop never exits. Grant → install;
        // revoke → tear down (macOS kills delivery anyway; we make the state
        // honest); re-grant → reinstall. The stream stays open through a
        // revocation because the condition is recoverable in-process —
        // `finish` is reserved for the source's own end of life (deinit).
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.permission.isGranted() {
                    _ = self.installTapIfAuthorized()
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
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
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
    func setConsumer(_ consumer: Consumer?) {
        lock.lock()
        self.consumer = consumer
        lock.unlock()
    }

    // MARK: - Tap installation (border)

    /// Returns true once the tap is installed. Never touches the CGEvent API
    /// while the permission is missing.
    private func installTapIfAuthorized() -> Bool {
        lock.lock()
        defer { lock.unlock() }

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
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            logger.error("event tap creation failed despite permission; will retry")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        logger.info("media-key tap installed")
        return true
    }

    private func tearDownTapIfInstalled() {
        lock.lock()
        defer { lock.unlock() }
        guard let tap else { return }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        logger.info("media-key tap removed (permission revoked); will reinstall on re-grant")
    }

    /// Returns whether the event must be swallowed (suppression active and the
    /// key is ours — both phases, see MediaKeyTranslation.ownedKey).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables taps it considers slow; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = self.tap
            lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
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

        guard MediaKeyTranslation.ownedKey(ignoringPhaseFromData1: data1) != nil else { return false }
        lock.lock()
        let consumer = self.consumer
        lock.unlock()
        guard let consumer else { return false }

        if let key = MediaKeyTranslation.mediaKey(fromData1: data1) {
            let modifiers = systemEvent.modifierFlags
            consumer(key, modifiers.contains(.option) && modifiers.contains(.shift))
        }
        return true
    }
}
