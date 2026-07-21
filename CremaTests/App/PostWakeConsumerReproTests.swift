import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import Crema

// Reproduction harness for the field report (author, Release/dev): after a
// lid/lock/display-sleep/unlock cycle a VOLUME key shows the Crema HUD *and* the
// native OSD together — the tap observes the key (the yield fires) but no longer
// swallows it (the consumer does not). This drives the SAME objects the report
// goes through, joined the SAME way the composition root joins them:
//
//   real CGEventTapMediaKeySource  (over an injectable tap border)
//   real MediaKeyInterceptionOSDSuppressor  (over mock channels)
//   real SuppressionLockController  (over a mock lock source)
//   AppCore.wireUnlockReinstall     (the exact production seam)
//   wake reinstalls == source.reinstallTap()  (what AppCore's wake observers call)
//
// The injectable tap captures the C callback, so a test fires a synthetic
// NX_SYSDEFINED aux-control event through the REAL source callback and reads back
// its TWO behaviors independently: the observation yield (always) and the swallow
// decision (consumer-gated). "Observes-but-does-not-consume" is therefore
// directly measurable: observation count grows while deliver() returns false.
//
// Every wait is bounded (eventually / waitForSleep / fixed loops) so a genuine
// wedge surfaces as an assertion failure, never a hung suite.

/// data1 payload: keyCode in the high word, 0x0A down / 0x0B up in the second
/// byte, repeat flag in bit 0 (mirrors MediaKeyTranslationTests' builder).
private func mediaData1(_ keyCode: Int, down: Bool, isRepeat: Bool = false) -> Int {
    (keyCode << 16) | ((down ? 0x0A : 0x0B) << 8) | (isRepeat ? 1 : 0)
}

/// NX_KEYTYPE_* codes for the keys this suite fires.
private func keyCode(_ key: MediaKey) -> Int {
    switch key {
    case .volumeUp: 0
    case .volumeDown: 1
    case .mute: 7
    case .screenBrightnessUp: 2
    case .screenBrightnessDown: 3
    case .keyboardBrightnessUp: 21
    case .keyboardBrightnessDown: 22
    }
}

/// Injectable event-tap border: like FakeEventTapOperating (same install /
/// enable / validate / uninstall bookkeeping) but it also CAPTURES the C callback
/// and userInfo of every install. A test can then fire a synthetic media-key
/// event through the real source's callback — and aim it at an OLD install to
/// model an event delivered to the stale port during an uninstall→install swap.
final class InjectableEventTapOperating: EventTapOperating, @unchecked Sendable {
    final class Token {}
    private struct Install {
        let token: Token
        let callback: CGEventTapCallBack
        let userInfo: UnsafeMutableRawPointer
    }

    private let lock = NSLock()
    private var installs: [Install] = []
    private var current: Token?
    private var _enabled = false
    private var _valid = false
    private var _installCount = 0
    private var _operations: [String] = []

    var installCount: Int { lock.withLock { _installCount } }
    var isInstalled: Bool { lock.withLock { current != nil } }
    var isCurrentlyEnabled: Bool { lock.withLock { _enabled } }
    var operations: [String] { lock.withLock { _operations } }
    /// Number of installs captured so far — the index of the current one is
    /// captureCount − 1; a prior index targets an already-uninstalled port.
    var captureCount: Int { lock.withLock { installs.count } }

    func simulateSystemDisable() { lock.withLock { _enabled = false } }
    func simulateSystemInvalidate() { lock.withLock { _valid = false } }

    func install(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> AnyObject? {
        lock.withLock {
            let token = Token()
            installs.append(Install(token: token, callback: callback, userInfo: userInfo))
            current = token
            _enabled = true
            _valid = true
            _installCount += 1
            _operations.append("install")
            return token
        }
    }

    func isEnabled(_ token: AnyObject) -> Bool { lock.withLock { (token as AnyObject) === current && _enabled } }
    func isValid(_ token: AnyObject) -> Bool { lock.withLock { (token as AnyObject) === current && _valid } }
    func setEnabled(_ token: AnyObject, _ enabled: Bool) {
        lock.withLock { if (token as AnyObject) === current { _enabled = enabled } }
    }

    func uninstall(_ token: AnyObject) {
        lock.withLock {
            _operations.append("uninstall")
            if (token as AnyObject) === current { current = nil; _enabled = false; _valid = false }
        }
    }

    /// Fire a synthetic media-key event through a captured install's callback.
    /// `index` nil = the current (last) install. Returns whether the callback
    /// swallowed it (true) or passed it through (false); nil if no such install.
    /// The install is looked up regardless of whether the port was later
    /// uninstalled — that is the whole point of the old-port delivery probe: the
    /// captured callback routes through the same source pointer either way.
    func deliver(data1: Int, index: Int? = nil) -> Bool? {
        let install: Install? = lock.withLock {
            guard !installs.isEmpty else { return nil }
            let i = index ?? (installs.count - 1)
            return installs.indices.contains(i) ? installs[i] : nil
        }
        guard let install, let event = Self.makeSystemDefinedEvent(data1: data1) else { return nil }
        // The proxy is never dereferenced by the callback (it reads userInfo); a
        // bogus non-null pointer is fine, and bitPattern: 0x1 is never nil.
        guard let proxy = OpaquePointer(bitPattern: 0x1) else { return nil }
        let result = install.callback(proxy, event.type, event, install.userInfo)
        return result == nil   // nil ⇒ swallowed
    }

    /// An NX_SYSDEFINED aux-control CGEvent (subtype 8) built via NSEvent — the
    /// only reliable way to synthesize one; its .type carries rawValue 14, which
    /// the callback reads directly (CGEventType has no named case for 14).
    static func makeSystemDefinedEvent(data1: Int) -> CGEvent? {
        NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: MediaKeyTranslation.auxiliaryControlSubtype,
            data1: data1,
            data2: -1
        )?.cgEvent
    }
}

@MainActor
final class PostWakeSeamHarness {
    let ops = InjectableEventTapOperating()
    let permission = MockAccessibilityPermission(granted: true)
    /// The source's own poll clock — parked after the first install; never
    /// advanced by the tests, so the poll never interferes with the probe.
    let clock = TestSleepClock()
    let source: CGEventTapMediaKeySource

    let volume = MockOSDVolumeChannel()
    let screen = MockOSDChannel()
    let keyboard = MockOSDChannel()
    /// The suppressor's probe/backoff clock and the read-deadline clock, kept
    /// apart so a test can drive recovery without tripping a read deadline.
    let suppClock = TestSleepClock()
    let readClock = TestSleepClock()
    let suppressor: MediaKeyInterceptionOSDSuppressor

    let lock = MockScreenLockSource(safe: true)
    let defaults = EphemeralDefaults()
    let prefs: Preferences
    let controller: SuppressionLockController

    /// Every observed key-down, appended by the stream consumer — the "observation
    /// is alive" signal, independent of the swallow decision.
    private(set) var observed: [MediaKey] = []
    private var observeTask: Task<Void, Never>?

    init(prefOn: Bool = true) {
        source = CGEventTapMediaKeySource(permission: permission, clock: clock, tapOps: ops)
        suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: source, volume: volume, screen: screen, keyboard: keyboard,
            clock: suppClock, readClock: readClock
        )
        prefs = Preferences(defaults: defaults.defaults)
        prefs.suppressesNativeOSD = prefOn
        controller = SuppressionLockController(suppressor: suppressor, lockSource: lock, preferences: prefs)
        // The exact seam AppCore installs: unlock edge → physical tap reinstall.
        AppCore.wireUnlockReinstall(from: controller, to: source)

        let stream = source.updates
        observeTask = Task { @MainActor [weak self] in
            for await key in stream { self?.observed.append(key) }
        }
    }

    /// Waits until the first poll iteration installed the tap and parked.
    func installed() async { await clock.waitForSleep() }

    /// Engages the lock-aware policy (the app's real start path).
    func start() { controller.start() }

    /// What AppCore's screensDidWake / didWake observers call.
    func wake() { source.reinstallTap() }

    /// A full physical press (down then up) through the current port; returns the
    /// key-down swallow decision (the meaningful one). Pairing the up keeps the
    /// decider's swallowed-downs set consistent, as a real key does.
    @discardableResult
    func press(_ key: MediaKey) -> Bool? {
        let code = keyCode(key)
        let down = ops.deliver(data1: mediaData1(code, down: true))
        _ = ops.deliver(data1: mediaData1(code, down: false))
        return down
    }

    var observedCount: Int { observed.count }

    func stop() {
        controller.stop()
        observeTask?.cancel()
        observeTask = nil
    }
}

/// The reproduction suite. Convergence proofs pin that the reinstall
/// interleavings the adjudication flagged all recover healthy consumption
/// (the official candidate is refuted — the consumer survives every reinstall);
/// the remaining tests pin the two structural explanations of the symptom that
/// do NOT go through reinstallation, and the observable difference between them.
///
/// The stale-unlock-read latch — the unlock edge reads a still-locked session
/// and strands the consumer — is FIXED at its source (a settle re-read in
/// `DistributedNotificationScreenLockSource`; docs/DECISIONS.md: settle-rereads),
/// and the recovery is pinned end-to-end in
/// `DistributedNotificationScreenLockSourceTests`. What stays here is the pure
/// proof of the reconciler dedup that made the stale read dangerous (the reason
/// the settle re-read must exist), plus the by-design transient symptom.
@MainActor
struct PostWakeConsumerReproTests {

    // MARK: - Convergence: the three reinstall triggers do not break consumption

    /// CANDIDATO OFICIAL, refuted for producing a stuck state: didWake +
    /// screensDidWake fire in a burst while engaged. Each is a full
    /// uninstall→install, but the consumer is a separate field the callback reads
    /// dynamically, so every reinstall preserves it. After the burst the tap still
    /// swallows every domain.
    @Test func reinstallBurstWhileEngagedKeepsConsuming() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()
        #expect(h.press(.volumeDown) == true)          // baseline: consuming
        #expect(h.ops.installCount == 1)

        h.wake()                                        // didWake
        h.wake()                                        // screensDidWake
        await settle()
        #expect(h.ops.installCount == 3)                // three full ports minted

        // The consumer survived every reinstall — all domains still swallowed.
        #expect(h.press(.volumeDown) == true)
        #expect(h.press(.screenBrightnessDown) == true)
        #expect(h.press(.mute) == true)
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        h.stop()
        withExtendedLifetime(h.source) {}
    }

    /// The physical order: wake (didWake/screensDidWake) arrives BEFORE the unlock
    /// edge, so the reinstalls run while the engagement is off (suspended by the
    /// lock). The unlock edge then reinstalls once more and re-engages. Consumption
    /// converges healthy.
    @Test func wakeBeforeUnlockConvergesToConsuming() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()
        #expect(h.press(.volumeDown) == true)

        h.lock.set(safe: false)                         // lock / display sleep
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.press(.volumeDown) == false)          // suspended: native OSD (correct)

        h.wake(); h.wake()                              // wakes while still locked
        await settle()
        #expect(h.press(.volumeDown) == false)          // still suspended, consumer nil

        h.lock.set(safe: true)                          // unlock: reinstall → re-engage
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(h.press(.volumeDown) == true)           // consumer restored, swallowing
        #expect(h.suppressor.suspendedDomains.isEmpty)
        h.stop()
        withExtendedLifetime(h.source) {}
    }

    /// A wake reinstall that lands AFTER the unlock re-engage still preserves the
    /// freshly-set consumer (the dynamic read again). Models a late screensDidWake.
    @Test func lateWakeAfterReengageStillConsumes() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        h.lock.set(safe: true)                          // unlock → reinstall → re-engage
        #expect(await eventually { h.suppressor.isEngaged })

        h.wake()                                        // a late wake AFTER re-engage
        await settle()
        #expect(h.press(.volumeDown) == true)           // consumer preserved through it
        h.stop()
        withExtendedLifetime(h.source) {}
    }

    /// setConsumer landing on an INVALIDATED port (the wake window can invalidate
    /// it) is not a dead end: the unlock seam reinstalls BEFORE re-engage, so the
    /// consumer lands on a live port. Pins that "setConsumer onto a dead tap" is
    /// recovered by the pinned order (unlock → reinstall → re-engage).
    @Test func reEngageOntoInvalidatedPortRestoresConsumption() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        h.ops.simulateSystemInvalidate()                // port dies during the away window
        h.lock.set(safe: true)                          // unlock: reinstall fixes it first
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(h.ops.isCurrentlyEnabled)
        #expect(h.press(.volumeDown) == true)           // consumer on a live port
        h.stop()
        withExtendedLifetime(h.source) {}
    }

    // MARK: - Old-port delivery during the swap

    /// An event delivered to the OLD port's callback during (or after) an
    /// uninstall→install swap routes through the same source pointer and reads the
    /// LIVE consumer — a stale port can neither corrupt the decision nor replay a
    /// frozen one. This is why the "old port delivering mid-swap" window is inert.
    @Test func oldPortDeliveryConsultsTheLiveConsumerNotAStaleSnapshot() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()
        let oldIndex = h.ops.captureCount - 1
        #expect(h.ops.deliver(data1: mediaData1(1, down: true), index: oldIndex) == true)
        _ = h.ops.deliver(data1: mediaData1(1, down: false), index: oldIndex)

        h.wake()                                        // reinstall: old port uninstalled
        await settle()
        #expect(h.ops.captureCount == 2)

        // Delivered to the OLD callback while a new port exists: still swallows,
        // because it consults the live consumer through the same source.
        #expect(h.ops.deliver(data1: mediaData1(1, down: true), index: oldIndex) == true)
        _ = h.ops.deliver(data1: mediaData1(1, down: false), index: oldIndex)

        // After a real disengage the SAME old-port callback passes through —
        // proof it reflects live state, not a snapshot from when it was minted.
        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.ops.deliver(data1: mediaData1(1, down: true), index: oldIndex) == false)
        h.stop()
        withExtendedLifetime(h.source) {}
    }

    // MARK: - The stale-unlock-read latch — the reconciler dedup the settle re-read fixes

    /// Mechanism proof (pure, no system API): the reconciler DEDUPLICATES a
    /// return-to-safe whose only unlock edge re-read a session dictionary that was
    /// still transiently locked. With no later edge to re-read, the reconciler
    /// stays unsafe — the return-to-safe emission is lost. This dedup is CORRECT
    /// (a confirming edge must not manufacture a flip); it is what makes a stale
    /// unlock read dangerous, and precisely why the source now schedules settle
    /// re-reads after each edge. The recovery those re-reads provide is pinned
    /// end-to-end in `DistributedNotificationScreenLockSourceTests`.
    @Test func reconcilerDedupesALostReturnToSafeEdge() {
        var r = ScreenLockReconciler(locked: false, onConsole: true)   // safe, lastSafe = true
        #expect(r.reconcile(locked: true, onConsole: true) == false)   // lock: emit unsafe
        // The single unlock edge re-reads a dict still reporting locked:
        #expect(r.reconcile(locked: true, onConsole: true) == nil)     // deduped: no emit
        #expect(r.lastSafe == false)                                   // stuck unsafe absent a re-read
    }

    // MARK: - The by-design transient symptom

    /// A volume apply that fails in the post-wake window (the audio stack still
    /// waking — the noOutputDevice window, modeled as a read that returns nil)
    /// suspends the VOLUME domain in place. The result is the exact
    /// field symptom — the next volume key passes through (native OSD) while the
    /// tap observes (Crema HUD) — but BY DESIGN: it is domain-scoped and self-heals
    /// via the read-only recovery probe when the channel comes back.
    @Test func volumeApplyFailurePostWakeIsTheSymptomButSelfHealsAndIsDomainScoped() async {
        let h = PostWakeSeamHarness(prefOn: true)
        await h.installed()
        h.start()
        await settle()
        #expect(h.press(.volumeDown) == true)           // consuming

        // The output device is not ready: the volume read fails, so the first
        // consumed volume key cannot verify and suspends the volume domain.
        h.volume.value = nil
        #expect(h.press(.volumeDown) == true)           // this press is still swallowed…
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })

        // The symptom: the next volume key passes through (native OSD) while the
        // tap still observes (Crema HUD) — both HUDs together, as reported.
        let before = h.observedCount
        #expect(h.press(.volumeDown) == false)          // volume no longer swallowed
        await settle()
        #expect(h.observedCount > before)               // observation alive

        // DISCRIMINATOR vs the stale-unlock-read latch: this is domain-scoped and still engaged.
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains == [.volume])       // ONLY volume
        #expect(h.press(.screenBrightnessDown) == true)           // brightness STILL consumed

        // And it SELF-HEALS: the audio stack finishes waking, the read-only probe
        // re-engages volume on its next backoff.
        h.volume.value = 0.5
        #expect(await eventually {
            h.suppClock.advance()
            return !h.suppressor.suspendedDomains.contains(.volume)
        }, "the volume domain never self-healed via the recovery probe")
        #expect(h.press(.volumeDown) == true)           // consuming again — transient
        h.stop()
        withExtendedLifetime(h.source) {}
    }
}
