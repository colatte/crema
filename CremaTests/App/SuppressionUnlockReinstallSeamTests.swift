import AppKit
import Testing
@testable import Crema

/// The tap-reinstall seams AppCore installs against the ENABLED-but-deaf failure
/// (docs/DECISIONS.md: J7-estado-do-outro-lado / preventive-reinstall): after a
/// lock/display-sleep/wake or a topology change the tap can keep a valid, enabled
/// port that silently stops delivering events, which neither health check can
/// see. reinstallTap is the deterministic
/// recovery, and it has FOUR convergent triggers. Each trigger→reinstall join is
/// pinned across the suites; the arming call in AppCore.init that installs them is
/// not (init boots the graph and system APIs, so no unit test constructs it):
///
///   1. NSWorkspace.didWake           — wired inline in AppCore.init
///   2. NSWorkspace.screensDidWake    — wired inline in AppCore.init
///   3. the unlock / return edge      — AppCore.wireUnlockReinstall (below)
///   4. didChangeScreenParameters     — AppCore.wireScreenParameterReinstall
///
/// The wake pair and the reinstall behavior itself are exercised by
/// PostWakeConsumerReproTests / CGEventTapMediaKeySourceHealthTests; this suite
/// pins the two seams that join a trigger to the reinstall through the exact
/// production wiring — break either and the isolated halves stay green while the
/// tap stays deaf in production. Both run a real source over the fake tap ops.
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

    /// The 4th reinstall trigger (docs/DECISIONS.md: preventive-reinstall): a
    /// display topology change (hotplug with no sleep) posts
    /// didChangeScreenParameters, which must reinstall the tap the
    /// same convergent way the wake and unlock triggers do — the topology
    /// reconfiguration can re-route delivery into the same ENABLED-but-deaf state,
    /// and no wake or lock edge would reach it. Driven over the SAME wiring AppCore
    /// installs (AppCore.wireScreenParameterReinstall), with a real source over the
    /// fake tap ops and an injected NotificationCenter so the post is deterministic
    /// and isolated from the process's real screen notifications.
    @Test func screenTopologyChangeReinstallsTheTapThroughTheRealSeam() async {
        let ops = FakeEventTapOperating()
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: MockAccessibilityPermission(granted: true),
            clock: clock,
            tapOps: ops
        )
        await clock.waitForSleep()   // installed and parked on the poll interval
        #expect(ops.installCount == 1)

        let center = NotificationCenter()
        let refreshed = Flag()
        // The exact wiring AppCore installs — the seam under test.
        let token = AppCore.wireScreenParameterReinstall(
            center: center,
            reinstalling: source
        ) { refreshed.value = true }

        center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

        // The topology change reinstalls the tap (paired teardown, no orphan, and
        // the fresh port routes back to the same source, so its dynamically-read
        // consumer survives by construction) AND still refreshes the panels.
        #expect(await eventually { ops.installCount == 2 })
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)
        #expect(ops.operations == ["install", "uninstall", "install"])
        #expect(ops.installedUserInfos.count == 2)
        #expect(ops.installedUserInfos[0] == ops.installedUserInfos[1])
        #expect(await eventually { refreshed.value })

        center.removeObserver(token)
        withExtendedLifetime(source) {}
    }
}
