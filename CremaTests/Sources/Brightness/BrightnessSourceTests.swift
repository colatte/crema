import Testing
@testable import Crema

/// Source logic over fake backends (no real API): availability
/// follows the backend, launch is baselined (no HUD), changes emit deduped and
/// clamped, and a degraded backend never crashes or emits. The screen source
/// additionally gates on origin: a key (`sample()`) shows a HUD, the sensor
/// (a poll-detected change with no recent key) does not.
struct BrightnessSourceTests {

    // MARK: - Screen

    @Test func screenSourceIsUnavailableWhenBackendIsUnavailable() async {
        let backend = FakeScreenBrightnessBackend(available: false)
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: TestSleepClock())
        #expect(await !source.isAvailable())
    }

    @Test func aSensorChangeWithNoKeyStaysSilent() async {
        // Auto-brightness moves the value with no key: the poll must absorb it
        // silently. Proven by a following key that lands on a distinct value —
        // it is the first thing the stream ever yields.
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        await clock.waitForSleep()
        backend.value = 0.8         // the sensor
        clock.advance()
        await clock.waitForSleep()  // barrier: the sensor poll has finished

        backend.value = 0.3         // the user's key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.3)))
    }

    @Test func aKeyThenAPolledChangeInsideTheWindowEmits() async {
        // Suppression-off flow: the key fires before the OS applies the value,
        // so `sample()` finds no change but arms the window; the poll a beat
        // later catches the applied value and emits.
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // key observed; value not applied yet
        await clock.waitForSleep()
        backend.value = 0.8         // OS applies
        clock.advance()

        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.8)))
    }

    @Test func aKeySampleSeeingTheAppliedValueEmitsImmediately() async {
        // Suppression-on flow: the consumer applied before the post-apply poke,
        // so the key `sample()` sees the change at once.
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 0.8
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.8)))
    }

    @Test func aChangeAfterTheKeyWindowExpiresIsTreatedAsSensor() async {
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let now = ManualNow()
        let source = DisplayServicesScreenBrightnessSource(
            backend: backend, clock: clock, pollInterval: 1, keyActivityWindow: 1.5, now: { now.now }
        )
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // arms until now + 1.5
        now.advance(by: 2)          // window has passed

        await clock.waitForSleep()
        backend.value = 0.8         // a change now is the sensor
        clock.advance()
        await clock.waitForSleep()  // barrier: that poll has finished

        backend.value = 0.3         // a fresh key is the first emit
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.3)))
    }

    @Test func aSensorChangeInAKeysTailStaysSilent() async {
        // The key HUD consumes the window, so a sensor change right after it
        // does not add a second HUD.
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 0.8
        source.sample()             // key HUD, window consumed
        await clock.waitForSleep()
        backend.value = 0.6         // sensor, in the tail
        clock.advance()
        await clock.waitForSleep()  // barrier: that poll finished

        backend.value = 0.4         // next key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.8)))
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.4)))
    }

    @Test func aNoOpKeyLeaksAtMostOneSensorHUD() async {
        // Accepted, documented: a key that changes nothing (already at the
        // limit) still arms the window — indistinguishable from a key whose
        // value has not applied yet — so one following sensor change leaks,
        // then the emit consumes the window and the rest stay silent.
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // no-op key: value unchanged, arms only
        await clock.waitForSleep()
        backend.value = 0.4         // sensor 1 — the one bounded leak
        clock.advance()
        await clock.waitForSleep()
        backend.value = 0.3         // sensor 2 — window consumed, silent
        clock.advance()
        await clock.waitForSleep()

        backend.value = 0.2         // a fresh key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.4)))
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.2)))
    }

    @Test func screenSourceDedupsAndClampsKeyDrivenReadings() async {
        let backend = FakeScreenBrightnessBackend(available: true, value: 0.5)
        let source = DisplayServicesScreenBrightnessSource(backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 1.9         // out of range → clamped
        source.sample()
        backend.value = 1.9         // same → no emit
        source.sample()
        backend.value = 0.3
        source.sample()

        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: 1))
        #expect(await iterator.next() == SystemHUD(kind: .screenBrightness, value: BrightnessConversion.normalize(0.3)))
    }

    // MARK: - Keyboard

    @Test func keyboardSourceIsUnavailableWhenBackendIsUnavailable() async {
        let backend = FakeKeyboardBrightnessBackend(available: false)
        let source = CoreBrightnessKeyboardBrightnessSource(backend: backend, clock: TestSleepClock())
        #expect(await !source.isAvailable())
    }

    @Test func keyboardBacklightAutoAdjustWithNoKeyStaysSilent() async {
        // The keyboard backlight auto-adjusts to ambient light, same as screen
        // auto-brightness: a poll change with no key is the sensor and must not
        // pop a HUD. Proven by a following key on a distinct value.
        let backend = FakeKeyboardBrightnessBackend(available: true, value: 0.3)
        let clock = TestSleepClock()
        let source = CoreBrightnessKeyboardBrightnessSource(backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        await clock.waitForSleep()
        backend.value = 1.0         // the sensor
        clock.advance()
        await clock.waitForSleep()  // barrier: the sensor poll finished

        backend.value = 0.6         // the user's key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .keyboardBrightness, value: BrightnessConversion.normalize(0.6)))
    }

    @Test func keyboardKeyEmitsKeyboardKind() async {
        let backend = FakeKeyboardBrightnessBackend(available: true, value: 0.3)
        let source = CoreBrightnessKeyboardBrightnessSource(backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 1.0
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: .keyboardBrightness, value: 1))
    }
}
