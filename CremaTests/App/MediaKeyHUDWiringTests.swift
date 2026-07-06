import Testing
@testable import Crema

/// End-to-end wiring: a physical brightness key (via the tap) reaches
/// the Coordinator and produces the right HUD, which reverts by the timer.
/// Everything mocked; no system API touched.
@MainActor
struct MediaKeyHUDWiringTests {

    @Test func brightnessKeyShowsHUDThenRevertsByTimer() async {
        let keys = MockMediaKeySource()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.6)
        let brightness = FakeSampledHUDSource(emitting: hud)
        let clock = TestSleepClock()

        let coordinator = Coordinator(
            nowPlayingSource: MockNowPlayingSource(),
            systemHUDSource: brightness,
            nowPlayingController: MockNowPlayingController(),
            volumeController: MockVolumeController(),
            screenBrightnessController: MockScreenBrightnessController(),
            keyboardBrightnessController: MockKeyboardBrightnessController(),
            clock: clock
        )
        coordinator.start()

        let router = MediaKeyHUDRouter(
            mediaKeys: keys,
            screenBrightness: brightness,
            keyboardBrightness: SpySampledSource()
        )
        router.start()

        // Key press → router pokes the source → it emits → Coordinator shows HUD.
        keys.emit(.screenBrightnessUp)
        #expect(await eventually { coordinator.state == .hud(hud) })

        // Then the revert timer restores hidden (no media playing).
        await clock.waitForSleep()
        clock.advance()
        #expect(await eventually { coordinator.state == .hidden })
        withExtendedLifetime(router) {}
    }
}
