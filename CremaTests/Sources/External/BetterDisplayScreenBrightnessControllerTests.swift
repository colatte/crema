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
