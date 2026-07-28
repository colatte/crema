import Testing
@testable import Crema

/// PolledBrightnessSource logic over the fake backend (no real API),
/// parameterized over BOTH channels — screen and keyboard backlight share one
/// implementation, and running every behavior for each kind is what pins that
/// the sharing is real (the copies used to pin most behaviors on the screen
/// side only). Availability follows the backend, launch is baselined (no HUD),
/// changes emit deduped and clamped, a degraded backend never crashes or
/// emits, and origin gates: a key (`sample()`) shows a HUD; the sensor — a
/// poll-detected change with no recent key: auto-brightness on the display,
/// the auto-adjusting backlight (hardware-confirmed) on the keyboard — does
/// not.
struct BrightnessSourceTests {
    private static let kinds: [SystemHUD.Kind] = [.screenBrightness, .keyboardBrightness]

    @Test(arguments: kinds)
    func sourceIsUnavailableWhenBackendIsUnavailable(kind: SystemHUD.Kind) async {
        let backend = FakeBrightnessBackend(available: false)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock())
        #expect(await !source.isAvailable())
    }

    @Test(arguments: kinds)
    func aSensorChangeWithNoKeyStaysSilent(kind: SystemHUD.Kind) async {
        // The sensor moves the value with no key: the poll must absorb it
        // silently. Proven by a following key that lands on a distinct value —
        // it is the first thing the stream ever yields.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        await clock.waitForSleep()
        backend.value = 0.8         // the sensor
        clock.advance()
        await clock.waitForSleep()  // barrier: the sensor poll has finished

        backend.value = 0.3         // the user's key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.3)))
    }

    @Test(arguments: kinds)
    func aKeyThenAPolledChangeInsideTheWindowEmits(kind: SystemHUD.Kind) async {
        // Suppression-off flow: the key fires before the OS applies the value,
        // so `sample()` finds no change but arms the window; the poll a beat
        // later catches the applied value and emits.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // key observed; value not applied yet
        await clock.waitForSleep()
        backend.value = 0.8         // OS applies
        clock.advance()

        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.8)))
    }

    @Test(arguments: kinds)
    func aKeySampleSeeingTheAppliedValueEmitsImmediately(kind: SystemHUD.Kind) async {
        // Suppression-on flow: the consumer applied before the post-apply poke,
        // so the key `sample()` sees the change at once — and the HUD carries
        // this channel's kind.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 0.8
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.8)))
    }

    @Test(arguments: kinds)
    func aChangeAfterTheKeyWindowExpiresIsTreatedAsSensor(kind: SystemHUD.Kind) async {
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let now = ManualNow()
        let source = PolledBrightnessSource(
            kind: kind, backend: backend, clock: clock, pollInterval: 1,
            keyActivityWindow: 1.5, now: { now.now }
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
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.3)))
    }

    @Test(arguments: kinds)
    func aSensorChangeInAKeysTailStaysSilent(kind: SystemHUD.Kind) async {
        // The key HUD consumes the window, so a sensor change right after it
        // does not add a second HUD.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: clock, pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 0.8
        source.sample()             // key HUD, window consumed
        await clock.waitForSleep()
        backend.value = 0.6         // sensor, in the tail
        clock.advance()
        await clock.waitForSleep()  // barrier: that poll finished

        backend.value = 0.4         // next key
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.8)))
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.4)))
    }

    @Test(arguments: kinds)
    func aNoOpKeyLeaksAtMostOneSensorHUD(kind: SystemHUD.Kind) async {
        // Accepted, documented: a key that changes nothing (already at the
        // limit) still arms the window — indistinguishable from a key whose
        // value has not applied yet — so one following sensor change leaks,
        // then the emit consumes the window and the rest stay silent.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: clock, pollInterval: 1)
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
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.4)))
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.2)))
    }

    @Test(arguments: kinds)
    func sourceDedupsUnchangedMidScaleKeyReadings(kind: SystemHUD.Kind) async {
        // A repeated key read at the same mid-scale value does not re-emit; only
        // a boundary no-op refreshes (proven separately).
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 0.7
        source.sample()
        backend.value = 0.7         // same mid-scale → no emit
        source.sample()
        backend.value = 0.3
        source.sample()

        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.7)))
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.3)))
    }

    @Test(arguments: kinds)
    func sourceClampsKeyDrivenReadings(kind: SystemHUD.Kind) async {
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        backend.value = 1.9         // out of range → clamped into 0...1
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: kind, value: 1))
    }

    @Test(arguments: kinds)
    func boundaryKeyPressAtMaxStillEmitsTheClampedValue(kind: SystemHUD.Kind) async {
        // Suppression-on, level pinned at max: the consumed key clamps to
        // 1.0 == before (a no-op write), yet a key-driven sample still emits
        // the full-bar HUD — S3, matching native's flash at the limit.
        let backend = FakeBrightnessBackend(available: true, value: 1.0)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // value unchanged at the boundary
        #expect(await iterator.next() == SystemHUD(kind: kind, value: 1))
    }

    @Test(arguments: kinds)
    func boundaryKeyPressAtMinStillEmitsTheClampedValue(kind: SystemHUD.Kind) async {
        // Same S3 parity at the bottom of the scale (the empty-bar flash).
        let backend = FakeBrightnessBackend(available: true, value: 0.0)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()

        source.sample()             // value unchanged at the boundary
        #expect(await iterator.next() == SystemHUD(kind: kind, value: 0))
    }
}
