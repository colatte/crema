import Testing
@testable import Crema

/// The lock-aware engagement policy, wired over a recording suppressor and a
/// test-driven lock source. Pins the fix's contract: locked/off-console
/// suspends suppression, unlock re-engages iff the pref is on, and the
/// lock/unlock path never touches the user preference. Nothing here touches a
/// real tap, channel, or the system lock APIs.
@MainActor
struct SuppressionLockControllerTests {

    @MainActor
    private struct Harness {
        let defaults = EphemeralDefaults()
        let preferences: Preferences
        let suppressor = RecordingOSDSuppressor()
        let lock: MockScreenLockSource
        let controller: SuppressionLockController

        init(prefOn: Bool, safe: Bool = true) {
            preferences = Preferences(defaults: defaults.defaults)
            preferences.suppressesNativeOSD = prefOn
            lock = MockScreenLockSource(safe: safe)
            controller = SuppressionLockController(
                suppressor: suppressor,
                lockSource: lock,
                preferences: preferences
            )
        }
    }

    // MARK: - Suspend on lock / off-console

    @Test func lockSuspendsSuppressionWithoutTouchingPref() async {
        let h = Harness(prefOn: true)
        h.controller.start()
        #expect(h.suppressor.isEngaged)

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.preferences.suppressesNativeOSD)   // untouched by the lock path
    }

    @Test func offConsoleSuspendsLikeLockAndReturnReengages() async {
        // Fast-user-switch is off-console; the source reduces it to safe=false,
        // and returning to the console re-engages exactly like an unlock.
        let h = Harness(prefOn: true)
        h.controller.start()
        #expect(h.suppressor.isEngaged)

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })

        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
    }

    // MARK: - Re-engage on return, gated by the pref

    @Test func unlockReengagesWhenPrefOn() async {
        let h = Harness(prefOn: true)
        h.controller.start()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })

        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(h.preferences.suppressesNativeOSD)
    }

    @Test func prefStaysOnAcrossLockCycle() async {
        let h = Harness(prefOn: true)
        h.controller.start()
        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(h.preferences.suppressesNativeOSD)
    }

    @Test func prefOffSeesZeroChangeThroughLockCycle() async {
        // The zero-change path: suppression off means the suppressor is never
        // engaged anywhere in a lock cycle, and the pref stays off.
        let h = Harness(prefOn: false)
        h.controller.start()
        #expect(!h.suppressor.isEngaged)

        h.lock.set(safe: false)
        await settle()
        #expect(!h.suppressor.isEngaged)

        h.lock.set(safe: true)
        await settle()
        #expect(!h.suppressor.isEngaged)
        #expect(!h.preferences.suppressesNativeOSD)
        #expect(h.suppressor.engageHistory.isEmpty)   // never engaged, ever
    }

    // MARK: - The preference is only ever written by the user (A1)

    @Test func lockCycleNeverWritesThePref() async {
        // A full suspend/re-engage cycle must not touch the persisted opt-in.
        // The pre-A1 auto-disengage path (a failed apply flipping the pref off,
        // routed through this controller) is gone: the suppressor now suspends
        // the failing domain in place and no failure path writes the pref.
        let h = Harness(prefOn: true)
        h.controller.start()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })

        #expect(h.preferences.suppressesNativeOSD)   // never rewritten by the app
    }

    // MARK: - Launch-while-locked

    @Test func launchedWhileLockedDefersEngagementToUnlock() async {
        let h = Harness(prefOn: true, safe: false)
        h.controller.start()
        await settle()
        #expect(!h.suppressor.isEngaged)
        #expect(h.suppressor.engageHistory.isEmpty)   // no engagement while locked

        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
    }

    // MARK: - Settings toggle while locked

    @Test func togglingOnWhileLockedPersistsAndDefers() async {
        let h = Harness(prefOn: false, safe: false)
        h.controller.start()
        await settle()

        h.controller.setPreferredSuppression(true)
        #expect(h.preferences.suppressesNativeOSD)   // persisted immediately
        #expect(!h.suppressor.isEngaged)             // engagement deferred to unlock
        #expect(h.suppressor.engageHistory.isEmpty)

        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
    }

    @Test func togglingOnWhileSafeEngagesImmediately() {
        let h = Harness(prefOn: false)
        h.controller.start()
        #expect(!h.suppressor.isEngaged)

        h.controller.setPreferredSuppression(true)
        #expect(h.suppressor.isEngaged)
        #expect(h.preferences.suppressesNativeOSD)
    }
}
