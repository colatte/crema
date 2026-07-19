import Testing
@testable import Crema

/// A1 #3: the persisted opt-in is sacred — no failure path writes it. Each of
/// the four documented triggers (throwing apply, failed verification,
/// unreadable read, deadline timeout) is fired through the real suppressor
/// wired to the real lock controller — the only object that ever wrote the pref
/// (via the now-removed auto-disengage). If any path writes it, these catch it.
@MainActor
struct OSDSuppressionPrefSacredTests {

    @MainActor
    private struct Harness {
        let defaults = EphemeralDefaults()
        let prefs: Preferences
        let keys = MockMediaKeyConsuming()
        let volume = MockOSDVolumeChannel()
        let screen = MockOSDChannel()
        let keyboard = MockOSDChannel()
        let clock = TestSleepClock()
        let suppressor: MediaKeyInterceptionOSDSuppressor
        let controller: SuppressionLockController

        init() {
            prefs = Preferences(defaults: defaults.defaults)
            prefs.suppressesNativeOSD = true
            suppressor = MediaKeyInterceptionOSDSuppressor(
                keys: keys, volume: volume, screen: screen, keyboard: keyboard, clock: clock
            )
            controller = SuppressionLockController(
                suppressor: suppressor,
                lockSource: MockScreenLockSource(safe: true),
                preferences: prefs
            )
            controller.start()
        }
    }

    @Test func throwingApplyLeavesThePrefUntouched() async {
        let h = Harness()
        h.screen.applyThrows = true
        h.keys.press(.screenBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.isEngaged)          // domain-scoped, not a global disengage
        #expect(h.prefs.suppressesNativeOSD)     // pref never rewritten
    }

    @Test func failedVerificationLeavesThePrefUntouched() async {
        let h = Harness()
        h.volume.writeIsDead = true   // write "succeeds" but the value never moves
        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }

    @Test func unreadableReadLeavesThePrefUntouched() async {
        let h = Harness()
        h.keyboard.value = nil
        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.keyboardBrightness) })
        #expect(h.prefs.suppressesNativeOSD)
    }

    @Test func deadlineTimeoutLeavesThePrefUntouched() async {
        let h = Harness()
        h.screen.applyHangs = true
        h.keys.press(.screenBrightnessUp)
        await h.clock.waitForSleep(delay: OSDTest.deadline)
        h.clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }
}
