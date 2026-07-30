import Foundation
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

    /// `sample()` plus the barrier saying the reading it queued has been taken.
    /// The source reads off the caller's thread on purpose (the real read is a
    /// blocking private-API call), so a test that moves the backend value after a
    /// sample must know the previous reading already happened — otherwise the
    /// mutation races it and the assertion pins whichever order won. Used exactly
    /// where a mutation or a silence-assertion follows a sample; where the next
    /// line awaits the emission that sample owes, that await IS the barrier.
    /// Bounded by wall clock, never a sleep: the condition is the backend's own
    /// reading count, and expiry fails here, loudly.
    private func sampleAndRead(_ source: PolledBrightnessSource, _ backend: FakeBrightnessBackend) async {
        let mark = backend.readCount
        source.sample()
        #expect(await backend.awaitRead(after: mark), "the sample's reading never landed")
    }

    @MainActor
    @Test(arguments: kinds)
    func aKeyDrivenSampleReadsOffTheCallersThread(kind: SystemHUD.Kind) async {
        // The freeze this seam exists to prevent. `sample()` is called ON THE
        // MAINACTOR by the suppressor's post-apply poke and by the slider echo —
        // the latter once per drag frame — and the real read is a blocking
        // private-API call (a dlsym'd DisplayServices entry point; a round trip
        // that re-enumerates the keyboard IDs). Inline, a stalled daemon froze
        // HUD, now playing and menu on the healthy path, with the key already
        // swallowed. Counted, not timed: no lucky schedule satisfies it.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: TestSleepClock(), pollInterval: 1)
        var iterator = source.updates.makeAsyncIterator()
        // The launch baseline is deliberately still read on this thread (see the
        // source's init), so the claim is about every reading after construction.
        let atLaunch = backend.mainThreadReads

        backend.value = 0.8
        source.sample()
        #expect(await iterator.next() == SystemHUD(kind: kind, value: BrightnessConversion.normalize(0.8)))
        #expect(backend.mainThreadReads == atLaunch)
    }

    @Test(arguments: kinds)
    func aPollDoesNotReParkWhileItsReadingIsStillInFlight(kind: SystemHUD.Kind) async {
        // One reading in flight per channel, ever: the poll awaits the reading it
        // queued. Without the await a stalled read lets the cadence pile up work
        // items that all land at once when it clears — and every `waitForSleep()`
        // in this file stops being a barrier, because the next mutation races a
        // reading that is still running.
        //
        // The gate is a DispatchSemaphore, like BlockingCallTests: the subject is a
        // read deliberately stuck, so a waiter that needed that read to finish
        // could not observe the state being asserted.
        let backend = FakeBrightnessBackend(available: true, value: 0.5)
        let clock = TestSleepClock()
        let source = PolledBrightnessSource(kind: kind, backend: backend, clock: clock, pollInterval: 1)
        await clock.waitForSleep()          // parked; the launch baseline is read

        let held = DispatchSemaphore(value: 0)
        backend.readGate = held
        defer { backend.readGate = nil; held.signal() }

        let started = backend.readsStarted
        clock.advance()                     // the poll wakes and queues a reading
        // The barrier the assertion needs: the reading is provably IN FLIGHT, so a
        // quiet clock cannot be a poll task that simply has not run yet. Counting
        // returned readings could not say this — the gate parks before the return.
        #expect(await backend.awaitReadStarted(after: started))
        await settle()
        #expect(clock.pendingSleeps == 0, "the poll must be suspended on its reading, not sleeping again")

        backend.readGate = nil
        held.signal()
        #expect(await eventuallyOffActor { clock.pendingSleeps == 1 })
        withExtendedLifetime(source) {}     // nothing else references it after init
    }

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

        // Barriered: without it the key's reading can land after the line below
        // and see 0.8 itself, which emits the right value by the wrong path and
        // leaves the armed poll — the whole subject here — untested.
        await sampleAndRead(source, backend)   // key observed; not applied yet
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

        // Every mutation here follows a sample, so every one needs the barrier:
        // otherwise the new value races the reading the previous sample queued and
        // the assertion pins whichever order won.
        backend.value = 0.7
        await sampleAndRead(source, backend)
        backend.value = 0.7         // same mid-scale → no emit
        await sampleAndRead(source, backend)
        backend.value = 0.3
        await sampleAndRead(source, backend)

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
