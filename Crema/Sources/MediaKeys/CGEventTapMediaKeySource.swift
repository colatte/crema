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

    private let logger = Logger.crema("MediaKeys")

    init(
        permission: any AccessibilityPermission,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2,
        tapOps: any EventTapOperating = LiveEventTapOperating()
    ) {
        // Bounded and newest-first, and dropping is safe here for a reason worth
        // stating: every element is a poke to re-sample a brightness level, never a
        // key's FATE. The swallow decision travels the consumer callback
        // synchronously (below), so no dropped element can leave a key wrongly
        // consumed or wrongly passed.
        //
        // Bounded because the single consumer (MediaKeyHUDRouter) samples a
        // brightness source per element, and a held key delivers autorepeats faster
        // than that sampling returns: unbounded, stale pokes would queue behind it
        // and replay a burst the user already finished. Newest-first because the
        // latest press is the one that describes where the level actually is — a
        // dropped poke costs at most a HUD refresh the next one supersedes.
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
        // clock/interval captured by value so the sleep never retains self —
        // a strong ref parked across the await would make deinit (which owns
        // the tap uninstall and this task's cancel) unreachable. The tick's own
        // strong binding is scoped to the tick, so it spans the tick's hop to the
        // main thread but never the sleep — that is the line that matters. Bound
        // with `if let self` because SwiftLint's self_binding requires it.
        pollTask = Task { [weak self, clock, pollInterval] in
            while !Task.isCancelled {
                if let self { await self.pollTick() }
                try? await clock.sleep(for: pollInterval)
            }
        }
    }

    /// One health-check pass: it DETECTS on the poll's own thread and MUTATES on
    /// the main one.
    ///
    /// Reconfiguring the port — install, uninstall, setEnabled — belongs to the
    /// thread that owns its run-loop source, which `LiveEventTapOperating` puts on
    /// the MAIN run loop and which is therefore also the thread the callback is
    /// delivered on. From anywhere else, two things go wrong: the callback takes
    /// `lock`, so a mutation holding it across a WindowServer round-trip stalls the
    /// main thread *inside* a tap callback — and a callback the system deems slow
    /// gets the tap disabled; and invalidating a mach port whose callback is
    /// mid-flight loses that event's swallow decision (the key applies AND reaches
    /// the system — the double HUD this whole family cures). Mutating on the main
    /// thread makes both impossible by construction. Same invariant the four
    /// preventive-reinstall edges buy with `queue: .main`.
    /// (docs/DECISIONS.md: tap-mutation-on-its-own-thread)
    ///
    /// Only a tick with something to change hops: `isGranted` and `install` are
    /// both blocking IPC, so hopping unconditionally would hand the main thread a
    /// periodic round-trip forever to close a rare race.
    private func pollTick() async {
        guard pollNeedsMutation() else { return }
        await MainActor.run { self.applyPollMutation() }
    }

    /// Whether this tick has anything to reconfigure — the filter that keeps a
    /// healthy poll off the main thread. Advisory by design: the state it reads can
    /// change under it (a wake-edge reinstall on the main thread), so it may hop for
    /// a fault someone else already fixed — `applyPollMutation` re-derives every
    /// decision under the lock and no-ops. It cannot latch either: a read answering
    /// "healthy" is the same read the mutation would take, and the next tick asks
    /// again one interval later.
    ///
    /// The port reads stay OUT of the lock so a main-thread mutation never queues
    /// behind a round-trip held here; the local binding keeps the token alive even if
    /// it is uninstalled meanwhile. All three reads below — the permission and the
    /// two port questions — are blocking C calls made on a cooperative-pool thread,
    /// which is what `blockingCall` exists to keep off it, and they stay here by
    /// decision rather than by oversight: this is ONE periodic caller, so it parks at
    /// most one pool thread at a time, while the hop would cost a queue round trip
    /// every tick, forever, on the healthy path this filter exists to make cheap.
    /// Moving only the part that COULD move buys nothing either — the port token is a
    /// non-Sendable `AnyObject` and cannot cross into a `@Sendable` closure, so the
    /// two port round trips would stay on this thread regardless. None of that is a
    /// licence for a second such caller.
    /// (docs/DECISIONS.md: read-deadline-pool-rule)
    private func pollNeedsMutation() -> Bool {
        // Revoked with a token still stored: the teardown is what keeps the state
        // honest, so a later re-grant installs a fresh port instead of trusting a
        // stale one that still reads healthy.
        guard permission.isGranted() else { return lock.withLock { self.tap != nil } }
        let stored = lock.withLock { self.tap }
        guard let stored else { return true }
        return !tapOps.isValid(stored) || !tapOps.isEnabled(stored)
    }

    /// The mutating half, on the tap's own thread. Every guard is evaluated again
    /// here — the permission, then the port state under the lock — so a tick that
    /// hopped on a since-fixed fault changes nothing.
    @MainActor
    private func applyPollMutation() {
        if permission.isGranted() {
            if installTapIfAuthorized() {
                healTapIfNeeded(reason: "poll")
            }
        } else {
            tearDownTapIfInstalled()
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

    /// Forces a brand-new tap unconditionally: tears down the current mach port
    /// and installs a fresh one regardless of `isEnabled`/`CFMachPortIsValid`.
    /// The stored `consumer` is read dynamically by the callback, so the fresh
    /// port adopts it — suppression *and* plain observation survive by
    /// construction. Uninstall precedes install deliberately: if `tapCreate`
    /// fails transiently (the WindowServer is briefly busy right after a wake),
    /// leaving zero tap is the *recoverable* state — the poll reinstalls within
    /// one interval — whereas keeping the old port would strand it, and a
    /// deaf-but-valid port is exactly what the poll cannot detect. So a rare,
    /// self-healing ≤pollInterval window is preferred over possibly stranding the
    /// very deafness this method exists to cure. No orphan port lingers either way.
    ///
    /// This exists for a failure mode the health-check is structurally blind to.
    /// After a lock / display-sleep / unlock the tap can stay `isEnabled == true`
    /// and `CFMachPortIsValid == true` yet silently stop delivering events
    /// (observed on hardware: brightness keys show the native OSD, the callback
    /// fires zero times — no observed key, no apply/suspend/probe — and only a
    /// relaunch, i.e. a fresh tap, cures it). Both health checks read PORT state,
    /// not event ROUTING, one level below the accounting this needs, so a live,
    /// enabled port that stopped routing is indistinguishable from a healthy one.
    /// Detecting the deafness without any delivered event is not reliably
    /// possible, so the recovery is deterministic instead: reinstall preventively
    /// on the unlock edge and on display/system wake (SuppressionLockController
    /// drives the unlock edge; AppCore observes the wake notifications — the wake
    /// path also catches a display-sleep/wake with no lock, which fires no unlock
    /// edge). It covers observation mode too, where the same deafness kills the
    /// brightness HUD even with suppression off — hence unconditional, never
    /// pref-gated.
    func reinstallTap() {
        lock.lock()
        defer { lock.unlock() }
        // Nothing is (or should be) installed while the permission is missing —
        // the poll installs the instant it lands, so there is nothing to force.
        guard permission.isGranted() else { return }
        if let tap {
            tapOps.uninstall(tap)
            self.tap = nil
        }
        if installTapIfAuthorizedLocked() {
            logger.notice("media-key tap reinstalled preventively")
        } else {
            logger.error("media-key tap reinstall failed; poll will retry")
        }
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

        let mask = CGEventMask(MediaKeyTranslation.systemDefinedMask)
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
    /// - Port valid but disabled: a re-enable restores it (the secure-input or
    ///   tap-timeout disable, delivered as a tapDisabledBy* event), keeping the
    ///   same port and its consumer wiring intact.
    ///   (docs/DECISIONS.md: J1-tap-zumbi)
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
