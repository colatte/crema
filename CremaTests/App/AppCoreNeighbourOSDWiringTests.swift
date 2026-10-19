import Testing
@testable import Crema

/// The three joins of the neighbour's indicator handoff, which its own suite never
/// exercises: the handoff is driven there by direct calls, and nothing outside this
/// suite proves the suppression decision, the neighbour's launch and the quit
/// actually reach it. Real channel, captured wire.
@MainActor
struct AppCoreNeighbourOSDWiringTests {

    @MainActor
    private final class Wire {
        var posted: [String] = []
    }

    @Test func theDecisionTheLaunchAndTheQuitEachReachTheHandoff() async throws {
        let store = EphemeralDefaults()
        let preferences = Preferences(defaults: store.defaults)
        preferences.suppressesNativeOSD = true
        let controller = SuppressionLockController(
            suppressor: RecordingOSDSuppressor(),
            lockSource: MockScreenLockSource(safe: true),
            preferences: preferences
        )
        let wire = Wire()
        let channel = BetterDisplayCommandChannel(
            clock: TestSleepClock(),
            newUUID: { "REQ" },
            post: { wire.posted.append($0) }
        )
        var quit: (@MainActor () async -> Void)?
        let handoff = AppCore.wireNeighbourOSDHandoff(
            channel: channel,
            following: controller,
            preferences: preferences,
            isNeighbourRunning: { true },
            holdingTheQuit: { quit = $0 }
        )

        // The decision: opted in and unlocked, the first one starts a take-over. The
        // neighbour already reads as needed, so the pass only reads.
        controller.start()
        #expect(await eventually { wire.posted.count == 1 })
        #expect(wire.posted[0].contains("osdIntegrationNotification"))
        channel.handle(response: #"{"uuid":"REQ","result":true,"payload":"on"}"#)
        #expect(await eventually { wire.posted.count == 2 })
        #expect(wire.posted[1].contains("osdShowBasic"))
        channel.handle(response: #"{"uuid":"REQ","result":true,"payload":"off"}"#)
        #expect(await eventually { handoff.status == .inPlace })

        // The launch: the neighbour's ready signal runs another pass.
        let launched = try #require(channel.onNeighbourLaunched)
        launched()
        #expect(await eventually { wire.posted.count == 3 })
        channel.handle(response: #"{"uuid":"REQ","result":true,"payload":"on"}"#)
        #expect(await eventually { wire.posted.count == 4 })
        channel.handle(response: #"{"uuid":"REQ","result":true,"payload":"off"}"#)

        // The quit: held by the handoff until the pass in flight ends, then a pass
        // that, with nothing owed, asks the neighbour nothing.
        let handBack = try #require(quit)
        await handBack()
        #expect(handoff.status == .idle)
        #expect(wire.posted.count == 4)
    }
}
