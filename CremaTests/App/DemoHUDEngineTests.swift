#if DEBUG
import Testing
@testable import Crema

/// The Demo menu's fake levels follow the real source's rule for a device
/// switch: nothing is emitted, and the next volume press carries the new route.
struct DemoHUDEngineTests {

    @Test func aDeviceSwitchEmitsNothingAndTheNextPressCarriesTheRoute() async throws {
        let engine = DemoHUDEngine()
        let events = BoundedStreamIterator(engine.updates)

        engine.demoNextOutputDevice()
        // The press is the barrier: the stream is ordered, so had the switch
        // emitted, its event would arrive first.
        engine.demoKeyPress(.volume)

        let first = try #require(await events.next())
        #expect(first.kind == .volume)
        #expect(first.route == AudioOutputRoute.allCases[1])
    }

    @Test func brightnessCarriesNoRoute() async throws {
        let engine = DemoHUDEngine()
        let events = BoundedStreamIterator(engine.updates)

        engine.demoKeyPress(.screenBrightness)

        let first = try #require(await events.next())
        #expect(first.route == nil)
    }
}
#endif
