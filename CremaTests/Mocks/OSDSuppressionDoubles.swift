@testable import Crema

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

/// Captures the consumer; tests fire keys through it like the tap would.
final class MockMediaKeyConsuming: MediaKeyConsuming, @unchecked Sendable {
    private(set) var consumer: Consumer?
    var isConsuming: Bool { consumer != nil }

    func setConsumer(_ consumer: Consumer?) {
        self.consumer = consumer
    }

    func press(_ key: MediaKey, fine: Bool = false) {
        consumer?(key, fine)
    }
}
