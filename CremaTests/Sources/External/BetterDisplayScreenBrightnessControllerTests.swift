import Foundation
import Testing
@testable import Crema

/// The actuator that sends a drag back to the app whose bar it was.
struct BetterDisplayScreenBrightnessControllerTests {

    private final class SpyChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [(value: Double, displayID: Int)] = []
        var written: [(value: Double, displayID: Int)] { lock.withLock { calls } }
        var failure: Error?

        func setBrightness(_ value: Double, displayID: Int) async throws {
            lock.withLock { calls.append((value, displayID)) }
            if let failure { throw failure }
        }
    }

    private let external = DisplayUUID(rawValue: "UUID-EXT")

    @Test func theBuiltInScreenIsAddressedByItsOwnID() async throws {
        // `display == nil` is the domain's built-in; the neighbour needs it
        // spelled out as a number.
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { $0 == nil ? 1 : 2 }
        )

        try await controller.setBrightness(0.4, on: nil)

        #expect(channel.written.count == 1)
        #expect(channel.written[0].displayID == 1)
        #expect(channel.written[0].value == 0.4)
    }

    @Test func anExternalScreenIsAddressedByItsOwn() async throws {
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(
            channel: channel,
            displayID: { [external] display in display == external ? 7 : nil }
        )

        try await controller.setBrightness(0.9, on: external)

        #expect(channel.written[0].displayID == 7)
    }

    @Test func aDisplayThatNoLongerResolvesIsNotWrittenTo() async {
        // Unplugged between the HUD and the drag: guessing another display would
        // dim the wrong screen.
        let channel = SpyChannel()
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in nil })

        await #expect(throws: BrightnessCommandError.unavailable) {
            try await controller.setBrightness(0.5, on: DisplayUUID(rawValue: "GONE"))
        }
        #expect(channel.written.isEmpty)
    }

    /// A channel that parks its first call until the test lets go, so a second
    /// write can arrive while the first is genuinely in flight.
    private final class ParkingChannel: BetterDisplayCommanding, @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [Double] = []
        private var release: CheckedContinuation<Void, Never>?
        private var parked = false

        var written: [Double] { lock.withLock { calls } }
        var callCount: Int { lock.withLock { calls.count } }

        func setBrightness(_ value: Double, displayID: Int) async throws {
            let shouldPark = lock.withLock {
                calls.append(value)
                let first = !parked
                parked = true
                return first
            }
            guard shouldPark else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.withLock { release = continuation }
            }
        }

        func letGo() {
            let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
                defer { release = nil }
                return release
            }
            continuation?.resume()
        }
    }

    @Test func writesCoalesceToTheLatestWithOnlyOneInFlight() async {
        // A drag fires on every frame and each write here is a round-trip to
        // another process. Without coalescing a two-second drag puts dozens in
        // the air at once, resolving out of order — the display lands on
        // whichever answered last instead of where the finger stopped.
        let channel = ParkingChannel()
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in 1 })

        let first = Task { try? await controller.setBrightness(0.2, on: nil) }
        #expect(await eventuallyOffActor { channel.callCount == 1 })

        // Three more frames of the same gesture, while the first is in flight.
        for value in [0.4, 0.6, 0.8] {
            try? await controller.setBrightness(value, on: nil)
        }
        #expect(channel.callCount == 1)      // none of them reached the channel

        channel.letGo()
        await first.value

        #expect(await eventuallyOffActor { channel.written == [0.2, 0.8] })
    }

    @Test func theNeighboursRefusalTravelsBackToTheCaller() async {
        // A failed apply must read as failure so the drag reports it, exactly
        // like the system actuator's own failures.
        let channel = SpyChannel()
        channel.failure = BetterDisplayCommandChannel.CommandError.unanswered
        let controller = BetterDisplayScreenBrightnessController(channel: channel, displayID: { _ in 1 })

        await #expect(throws: BetterDisplayCommandChannel.CommandError.unanswered) {
            try await controller.setBrightness(0.5, on: nil)
        }
    }
}
