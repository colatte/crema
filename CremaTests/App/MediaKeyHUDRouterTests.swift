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

        #expect(await eventuallyOffActor { screen.sampleCount == 2 })
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

        #expect(await eventuallyOffActor { keyboard.sampleCount == 2 })
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
        // One sentinel per channel BEHIND the volume keys, because a negative
        // claim needs a barrier: the router consumes one ordered stream, so when
        // the last sentinel has been sampled every volume key is already routed
        // and both counts are final — exactly one each, or the volume keys added
        // to a channel. Waiting a fixed number of yields instead was a
        // scheduler-slot budget, which a starved machine exhausts before the
        // consumer has run at all — the idiom the bounded helpers replace.
        keys.emit(.screenBrightnessUp)
        keys.emit(.keyboardBrightnessUp)

        #expect(await eventuallyOffActor { keyboard.sampleCount == 1 })
        #expect(screen.sampleCount == 1)
        withExtendedLifetime(router) {}
    }
}
