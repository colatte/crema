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
    let suppressor: MediaKeyInterceptionOSDSuppressor
    private(set) var suspensionChanges = 0

    init() {
        suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: volume, screen: screen, keyboard: keyboard, clock: clock
        )
        suppressor.onSuspensionStateChange = { [weak self] in self?.suspensionChanges += 1 }
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

    func isAvailable() -> Bool { available }

    func read() -> Double? { value }

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

    func isAvailable() -> Bool { available }

    func supportsMute() -> Bool { muteSupported }

    func read() -> Double? { value }

    func apply(_ newValue: Double) async throws {
        if applyThrows { throw Failure() }
        await MainActor.run {
            applied.append(newValue)
            if !writeIsDead { value = newValue }
        }
    }

    func readMuted() -> Bool? { muted }

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
