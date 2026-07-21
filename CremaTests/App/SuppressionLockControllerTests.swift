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

    // MARK: - The preference is only ever written by the user

    @Test func lockCycleNeverWritesThePref() async {
        // A full suspend/re-engage cycle must not touch the persisted opt-in.
        // The old auto-disengage path (a failed apply flipping the pref off,
        // routed through this controller) is gone: the suppressor now suspends
        // the failing domain in place and no failure path writes the pref.
        // (docs/DECISIONS.md: pref-sacred)
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

    // MARK: - Unlock-edge tap reinstall (ENABLED-but-deaf recovery; docs/DECISIONS.md: J7-estado-do-outro-lado)

    @Test func unlockEdgeFiresReinstallBeforeReengage() async {
        // Order is load-bearing: the physical reinstall must run BEFORE the
        // re-engage sets the consumer, so the fresh port adopts it. At the moment
        // onUnlocked fires, the suppressor is therefore still disengaged.
        let h = Harness(prefOn: true)
        h.controller.start()
        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })

        var sawEngagedAtReinstall: Bool?
        h.controller.onUnlocked = { sawEngagedAtReinstall = h.suppressor.isEngaged }
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(sawEngagedAtReinstall == false)   // reinstall ran before re-engage
    }

    @Test func repeatedSafeWithoutLockReinstallsOnce() async {
        // The controller guards on the EDGE (isSafe false→true), not the level: a
        // redundant safe=true with no lock in between must not reinstall again.
        var reinstalls = 0
        let h = Harness(prefOn: true)
        h.controller.onUnlocked = { reinstalls += 1 }
        h.controller.start()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(reinstalls == 1)

        h.lock.set(safe: true)   // redundant, no lock edge in between
        await settle()
        #expect(reinstalls == 1)
    }

    @Test func prefOffUnlockStillReinstallsWithoutEngaging() async {
        // Deafness kills observation too, so the reinstall must fire on unlock
        // even with suppression off — the controller runs independent of the pref.
        var reinstalls = 0
        let h = Harness(prefOn: false)
        h.controller.onUnlocked = { reinstalls += 1 }
        h.controller.start()

        h.lock.set(safe: false)
        await settle()
        h.lock.set(safe: true)
        #expect(await eventually { reinstalls == 1 })
        #expect(!h.suppressor.isEngaged)             // pref off → never engages
        #expect(h.suppressor.engageHistory.isEmpty)
    }

    @Test func launchAlreadyUnlockedDoesNotReinstall() async {
        // The tap is freshly installed at launch; only an unlock EDGE reinstalls,
        // so a normal already-unlocked start must not fire a spurious one.
        var reinstalls = 0
        let h = Harness(prefOn: true)   // safe: true
        h.controller.onUnlocked = { reinstalls += 1 }
        h.controller.start()
        await settle()

        #expect(h.suppressor.isEngaged)
        #expect(reinstalls == 0)
    }

    @Test func lockEdgeDoesNotReinstall() async {
        // Going to safe=false (lock / off-console) never reinstalls — the
        // recovery belongs to the return edge.
        var reinstalls = 0
        let h = Harness(prefOn: true)
        h.controller.onUnlocked = { reinstalls += 1 }
        h.controller.start()

        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(reinstalls == 0)
    }
}
