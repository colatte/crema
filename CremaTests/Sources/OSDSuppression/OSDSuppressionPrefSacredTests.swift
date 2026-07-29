import Testing
@testable import Crema

/// The persisted opt-in is sacred — no failure path writes it (docs/DECISIONS.md:
/// pref-sacred). Each of the four documented triggers (throwing apply, failed
/// verification,
/// unreadable read, deadline timeout) is fired through the real suppressor
/// wired to the real lock controller — the only object that ever wrote the pref
/// (via the now-removed auto-disengage). If any path writes it, these catch it.
/// Uses the shared OSDSuppressorLockHarness (CremaTests/Mocks/), whose separate
/// readClock keeps a future read-path case deterministic instead of falling
/// back to the production clock.
@MainActor
struct OSDSuppressionPrefSacredTests {

    @Test func throwingApplyLeavesThePrefUntouched() async {
        let h = OSDSuppressorLockHarness()
        h.screen.applyThrows = true
        h.keys.press(.screenBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.isEngaged)          // domain-scoped, not a global disengage
        #expect(h.prefs.suppressesNativeOSD)     // pref never rewritten
    }

    @Test func failedVerificationLeavesThePrefUntouched() async {
        let h = OSDSuppressorLockHarness()
        h.volume.writeIsDead = true   // write "succeeds" but the value never moves
        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }

    @Test func unreadableReadLeavesThePrefUntouched() async {
        let h = OSDSuppressorLockHarness()
        h.keyboard.value = nil
        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.keyboardBrightness) })
        #expect(h.prefs.suppressesNativeOSD)
    }

    @Test func deadlineTimeoutLeavesThePrefUntouched() async {
        let h = OSDSuppressorLockHarness()
        h.screen.applyHangs = true
        h.keys.press(.screenBrightnessUp)
        await h.clock.waitForSleep(delay: OSDTest.deadline)
        h.clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.prefs.suppressesNativeOSD)
        #expect(h.suppressor.isEngaged)
    }
}
