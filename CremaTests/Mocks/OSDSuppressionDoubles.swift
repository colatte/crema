import Foundation
@testable import Crema

/// Shared harness for the suppressor suites: the production suppressor over
/// mocked channels and a captured consumer, plus a counter of long-suspension
/// state changes (escalation/recovery, the menu signal).
@MainActor
final class OSDSuppressorHarness {
    let keys = MockMediaKeyConsuming()
    let volume = MockOSDVolumeChannel()
    let screen = MockOSDChannel()
    let keyboard = MockOSDChannel()
    let clock = TestSleepClock()
    /// Read deadlines sleep here, apart from `clock` (probe backoff + write
    /// deadline), so a test can advance one without tripping the other — read
    /// deadlines fire on the probe-recovery path too. Never advanced by
    /// tests with fast reads; the read-hang suite drives it directly.
    let readClock = TestSleepClock()
    let suppressor: MediaKeyInterceptionOSDSuppressor
    private(set) var suspensionChanges = 0
    /// Where the brightness keys aim. Mutable so a suite can move the pointer to
    /// another display; `.builtIn` by default because that is what every suite
    /// written before the pointer rule assumes — one Mac, the key applies here.
    /// The suppressor's own parameter has NO default on purpose (a default would
    /// be the reported bug), so the choice is made here, once, in the open.
    ///
    /// Behind a lock-guarded box rather than a stored property: the suppressor
    /// reads it from the TAP thread, synchronously, inside the swallow decision.
    let brightnessTarget = BrightnessTargetBox()

    init() {
        suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: volume, screen: screen, keyboard: keyboard,
            screenBrightnessTarget: { [brightnessTarget] in brightnessTarget.value },
            clock: clock, readClock: readClock
        )
        suppressor.onSuspensionStateChange = { [weak self] in self?.suspensionChanges += 1 }
    }
}

/// The lock-aware superset of OSDSuppressorHarness: the production suppressor
/// wired to the real SuppressionLockController over a mock lock source and
/// ephemeral prefs (opted in, started), so a suite exercises the actual
/// engage/disengage policy — not a bare setEngaged. Keeps `clock` and
/// `readClock` apart for the same reason the base harness does: read deadlines
/// must not trip when a test advances the probe/backoff clock.
@MainActor
final class OSDSuppressorLockHarness {
    let keys = MockMediaKeyConsuming()
    let volume = MockOSDVolumeChannel()
    let screen = MockOSDChannel()
    let keyboard = MockOSDChannel()
    let clock = TestSleepClock()
    let readClock = TestSleepClock()
    let lock = MockScreenLockSource(safe: true)
    let defaults = EphemeralDefaults()
    let prefs: Preferences
    let suppressor: MediaKeyInterceptionOSDSuppressor
    let controller: SuppressionLockController
    private(set) var suspensionChanges = 0

    init() {
        prefs = Preferences(defaults: defaults.defaults)
        prefs.suppressesNativeOSD = true
        suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: volume, screen: screen, keyboard: keyboard,
            screenBrightnessTarget: { .builtIn },
            clock: clock, readClock: readClock
        )
        controller = SuppressionLockController(
            suppressor: suppressor, lockSource: lock, preferences: prefs
        )
        // Set after every stored property is initialized: the [weak self]
        // capture needs a fully-formed self, and `controller` is the last.
        suppressor.onSuspensionStateChange = { [weak self] in self?.suspensionChanges += 1 }
        controller.start()
    }
}

/// The aim, readable from the tap thread. Its own type for the same reason the
/// channel doubles have one: the suppressor asks synchronously, off the actor.
final class BrightnessTargetBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: BrightnessKeyTarget = .builtIn
    var value: BrightnessKeyTarget {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// A running counter safe to capture in a @MainActor closure — used where the
/// thing being counted is not a collection (so `isEmpty` does not apply).
@MainActor
final class CounterBox { var count = 0 }

/// Shared constants for the suppressor suites.
enum OSDTest {
    static let step = 1.0 / 16.0
    static let fine = 1.0 / 64.0
    static let escalation = MediaKeyInterceptionOSDSuppressor.escalationThreshold
    static let deadline = MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline
}

/// Channel double with a live value: reads return it, applies move it —
/// unless the write path is scripted dead (records but never moves),
/// throwing, or hung (suspends until cancelled, like a blocked actuator).
/// The suspension point in apply is what the ordering test needs: an
/// autorepeat burst over interleaving applies would lose steps. Mutations
/// hop to the MainActor because the tests poll these from it.
final class MockOSDChannel: OSDChannel, @unchecked Sendable {
    struct Failure: Error {}

    var available = true
    var value: Double? = 0.5
    var writeIsDead = false
    var applyThrows = false
    var applyHangs = false
    private(set) var applied: [Double] = []

    /// The read-side analogue of applyHangs: when true, read() blocks the
    /// calling detached thread on a semaphore until releaseRead(), modeling a
    /// blocked synchronous C read (a coreaudiod stall) that readWithDeadline
    /// must race a deadline against without freezing the MainActor. Unlike
    /// applyHangs (a cancellable Task.sleep), this is genuinely uncancellable —
    /// like the real C call — so releaseRead() at test end frees the orphan.
    /// `passReadsBeforeHang` lets the pre-read succeed and only the read-back
    /// hang (set it to 1); 0 hangs the very first read.
    var readHangs = false
    var passReadsBeforeHang = 0

    /// The availability guard hangs, on its own gate. Separate from the read's
    /// because the keyboard channel is the one where the two really are different
    /// calls: CoreBrightness answers availability by enumerating backlight IDs over
    /// the private client's connection — IPC that can stall — while its screen
    /// sibling answers from two dlsym results resolved at init and cannot block at
    /// all. Modelling them as one switch would let a test claim a screen guard
    /// stalls, which the real one never does.
    var availableHangs = false
    private let availableGate = DispatchSemaphore(value: 0)

    /// The read straight after each write comes back nil, and only that one: the
    /// output vanishing for an instant between write and verify. The pre-read and
    /// every probe read still succeed, which is what makes this the shape that
    /// drives repeated write-health episodes — the probe keeps recovering the
    /// domain, so nothing else can be blamed for an escalation.
    var readBackReturnsNilOnce = false

    private let hangLock = NSLock()
    private var readsSeen = 0
    private var swallowNextRead = false
    private let readGate = DispatchSemaphore(value: 0)

    func isAvailable() -> Bool {
        if availableHangs { availableGate.wait() }
        return available
    }

    /// Frees one parked availability guard so its orphaned detached task
    /// completes — the read's own gate is released by releaseRead().
    func releaseAvailable() { availableGate.signal() }

    func read() -> Double? {
        let shouldHang: Bool = hangLock.withLock {
            guard readHangs, readsSeen >= passReadsBeforeHang else {
                readsSeen += 1
                return false
            }
            readsSeen += 1
            return true
        }
        if shouldHang { readGate.wait() }
        let swallow = hangLock.withLock {
            let pending = swallowNextRead
            swallowNextRead = false
            return pending
        }
        return swallow ? nil : value
    }

    /// Frees one parked read so its orphaned detached task completes and its
    /// thread is released — call once per hung read at test end.
    func releaseRead() { readGate.signal() }

    func apply(_ newValue: Double) async throws {
        if applyHangs {
            // Parks until the deadline's cancelAll lands; swallowing the
            // cancellation mimics a C call that returns into a dead task.
            try? await Task.sleep(for: .seconds(100_000))
            return
        }
        if applyThrows { throw Failure() }
        await MainActor.run {
            applied.append(newValue)
            if !writeIsDead { value = newValue }
        }
        if readBackReturnsNilOnce { hangLock.withLock { swallowNextRead = true } }
    }
}

/// Volume adds the mute plane, with its own dead-write switch: a live volume
/// path with a silently dead mute plane is a distinct real-world failure.
final class MockOSDVolumeChannel: OSDVolumeChannel, @unchecked Sendable {
    struct Failure: Error {}

    var available = true
    var muteSupported = true
    var value: Double? = 0.5
    var muted: Bool? = false
    var writeIsDead = false
    var muteWriteIsDead = false
    var applyThrows = false
    private(set) var applied: [Double] = []
    private(set) var mutedWrites: [Bool] = []

    /// Volume reads and its IPC guards can each hang independently: the
    /// availability guard (defaultOutputDeviceID), the mute-capability guard
    /// (AudioObjectHasProperty), the level read, and the mute-plane read are all
    /// Core Audio IPC. Each blocks on the shared gate until releaseHang(); one
    /// hangs per test, so one release frees it.
    var availableHangs = false
    var supportsMuteHangs = false
    var readHangs = false
    var readMutedHangs = false
    private let hangGate = DispatchSemaphore(value: 0)

    func isAvailable() -> Bool {
        if availableHangs { hangGate.wait() }
        return available
    }

    func supportsMute() -> Bool {
        if supportsMuteHangs { hangGate.wait() }
        return muteSupported
    }

    func read() -> Double? {
        if readHangs { hangGate.wait() }
        return value
    }

    func apply(_ newValue: Double) async throws {
        if applyThrows { throw Failure() }
        await MainActor.run {
            applied.append(newValue)
            if !writeIsDead { value = newValue }
        }
    }

    func readMuted() -> Bool? {
        if readMutedHangs { hangGate.wait() }
        return muted
    }

    /// Frees one parked read/guard so its orphaned detached task completes.
    func releaseHang() { hangGate.signal() }

    func setMuted(_ newValue: Bool) async throws {
        if applyThrows { throw Failure() }
        await MainActor.run {
            mutedWrites.append(newValue)
            if !muteWriteIsDead { muted = newValue }
        }
    }
}

/// Captures the consumer; tests fire keys through it like the tap would. The
/// consumer decides per phase whether to swallow, so the fakes expose the
/// down/up phases separately and return the swallow decisions.
final class MockMediaKeyConsuming: MediaKeyConsuming, @unchecked Sendable {
    private(set) var consumer: Consumer?
    var isConsuming: Bool { consumer != nil }

    func setConsumer(_ consumer: Consumer?) {
        self.consumer = consumer
    }

    /// A full press: key-down (optionally fine) then key-up, like the tap.
    /// Returns both swallow decisions for phase-consistency assertions.
    @discardableResult
    func press(_ key: MediaKey, fine: Bool = false) -> (down: Bool, up: Bool) {
        (down: pressDown(key, fine: fine), up: pressUp(key))
    }

    @discardableResult
    func pressDown(_ key: MediaKey, fine: Bool = false) -> Bool {
        consumer?(key, fine, true) ?? false
    }

    @discardableResult
    func pressUp(_ key: MediaKey) -> Bool {
        consumer?(key, false, false) ?? false
    }
}
