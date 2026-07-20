import Testing
@testable import Crema

/// The unlock-edge tap-reinstall seam AppCore installs between the lock
/// controller and the media-key source. The halves are pinned in isolation —
/// the controller fires onUnlocked on the return edge before re-engage
/// (SuppressionLockControllerTests), and reinstallTap forces a fresh port
/// preserving the consumer (CGEventTapMediaKeySourceHealthTests) — but the
/// wiring that joins them lives only in the composition root: break the seam and
/// both isolated suites stay green while the tap stays deaf in production. This
/// drives the real seam end to end over the SAME wiring AppCore uses
/// (AppCore.wireUnlockReinstall), with a real source over the fake tap ops and a
/// test-driven lock source.
///
/// Motive (BUG-CLASS-AUDIT A8): after lock/display-sleep/unlock the tap can go
/// ENABLED-but-deaf — valid port, enabled, zero events — which neither health
/// check can see; reinstalling on the unlock edge is the deterministic recovery.
@MainActor
struct SuppressionUnlockReinstallSeamTests {

    @Test func unlockEdgeReinstallsTheTapThroughTheRealSeam() async {
        let ops = FakeEventTapOperating()
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: MockAccessibilityPermission(granted: true),
            clock: clock,
            tapOps: ops
        )
        await clock.waitForSleep()   // installed and parked on the poll interval
        #expect(ops.installCount == 1)

        let defaults = EphemeralDefaults()
        let preferences = Preferences(defaults: defaults.defaults)
        preferences.suppressesNativeOSD = true
        let lock = MockScreenLockSource(safe: true)
        let controller = SuppressionLockController(
            suppressor: RecordingOSDSuppressor(),
            lockSource: lock,
            preferences: preferences
        )
        // The exact wiring AppCore installs — the seam under test.
        AppCore.wireUnlockReinstall(from: controller, to: source)
        controller.start()

        lock.set(safe: false)   // lock / display sleep
        await settle()
        lock.set(safe: true)    // unlock: the seam must physically reinstall the tap

        #expect(await eventually { ops.installCount == 2 })
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)
        // Paired teardown (no orphan) and the fresh port routes back to the same
        // source, so its dynamically-read consumer survives by construction.
        #expect(ops.operations == ["install", "uninstall", "install"])
        #expect(ops.installedUserInfos.count == 2)
        #expect(ops.installedUserInfos[0] == ops.installedUserInfos[1])

        controller.stop()
        withExtendedLifetime(source) {}
    }
}
