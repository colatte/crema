import Testing
@testable import Crema

/// The router pokes the right brightness source per key, and leaves
/// volume to the (event-driven) Core Audio source.
struct MediaKeyHUDRouterTests {

    @Test func screenBrightnessKeysSampleTheScreenSource() async {
        let keys = MockMediaKeySource()
        let screen = SpySampledSource()
        let keyboard = SpySampledSource()
        let router = MediaKeyHUDRouter(mediaKeys: keys, screenBrightness: screen, keyboardBrightness: keyboard)
        router.start()

        keys.emit(.screenBrightnessUp)
        keys.emit(.screenBrightnessDown)

        #expect(await poll { screen.sampleCount == 2 })
        #expect(keyboard.sampleCount == 0)
        withExtendedLifetime(router) {}
    }

    @Test func keyboardBrightnessKeysSampleTheKeyboardSource() async {
        let keys = MockMediaKeySource()
        let screen = SpySampledSource()
        let keyboard = SpySampledSource()
        let router = MediaKeyHUDRouter(mediaKeys: keys, screenBrightness: screen, keyboardBrightness: keyboard)
        router.start()

        keys.emit(.keyboardBrightnessUp)
        keys.emit(.keyboardBrightnessDown)

        #expect(await poll { keyboard.sampleCount == 2 })
        #expect(screen.sampleCount == 0)
        withExtendedLifetime(router) {}
    }

    @Test func volumeKeysAreNotRouted() async {
        let keys = MockMediaKeySource()
        let screen = SpySampledSource()
        let keyboard = SpySampledSource()
        let router = MediaKeyHUDRouter(mediaKeys: keys, screenBrightness: screen, keyboardBrightness: keyboard)
        router.start()

        keys.emit(.volumeUp)
        keys.emit(.volumeDown)
        keys.emit(.mute)

        // Give the consumer time to (not) act.
        for _ in 0..<200 { await Task.yield() }
        #expect(screen.sampleCount == 0)
        #expect(keyboard.sampleCount == 0)
        withExtendedLifetime(router) {}
    }

    /// Non-main-actor spin wait (these doubles aren't main-isolated).
    private func poll(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
    }
}
