import Testing
@testable import Crema

/// Tap-health self-heal: the cases the Stage-1 lock tests could not see — a tap
/// the system turns against us behind the source's back, with no delivered
/// callback. Two distinct failure modes with two responses: a *disabled* tap
/// (port still valid) is re-enabled in place; an *invalidated* mach port (dead
/// permanently) is reinstalled from scratch. Left unhandled either way, the tap
/// stays dead while our state says "installed", so keys reach the system and the
/// native OSD comes back alongside ours (double HUD). The poll and the re-engage
/// path cover both modes.
struct CGEventTapMediaKeySourceHealthTests {

    /// Drives the poll to the point where the tap is installed and parked on the
    /// interval sleep, then returns everything the test needs.
    private func installedSource(
        permission: MockAccessibilityPermission = MockAccessibilityPermission(granted: true)
    ) async -> (CGEventTapMediaKeySource, FakeEventTapOperating, TestSleepClock) {
        let ops = FakeEventTapOperating()
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: permission,
            clock: clock,
            tapOps: ops
        )
        // First poll iteration installs, then parks on the interval sleep.
        await clock.waitForSleep()
        return (source, ops, clock)
    }

    @Test func pollRevivesExternallyDisabledTap() async {
        let (source, ops, clock) = await installedSource()
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)

        // The system disables the tap with no callback delivered.
        ops.simulateSystemDisable()
        #expect(!ops.isCurrentlyEnabled)

        // Next poll iteration: it finds the tap installed-but-disabled and
        // re-enables it — no reinstall.
        clock.advance()
        await clock.waitForSleep()

        #expect(ops.isCurrentlyEnabled)
        #expect(ops.installCount == 1)
        withExtendedLifetime(source) {}
    }

    @Test func reEngageTriggersImmediateRevalidation() async {
        let (source, ops, _) = await installedSource()
        ops.simulateSystemDisable()
        #expect(!ops.isCurrentlyEnabled)

        // The unlock re-engage path sets the consumer; that must revive the tap
        // synchronously, not wait up to a full poll interval.
        source.setConsumer { _, _, _ in true }

        #expect(ops.isCurrentlyEnabled)
    }

    @Test func revivalKeepsSameTapInstalled() async {
        let (source, ops, _) = await installedSource()
        ops.simulateSystemDisable()

        source.setConsumer { _, _, _ in true }

        // Reviving re-enables the existing port rather than tearing it down and
        // recreating it — a reinstall would drop the consumer just set.
        #expect(ops.installCount == 1)
        #expect(ops.isInstalled)
        #expect(ops.setEnabledCalls.last == true)
    }

    @Test func healthCheckNoOpsWhenTapAlreadyEnabled() async {
        let (source, ops, clock) = await installedSource()
        // A healthy tap must not be toggled by the poll.
        clock.advance()
        await clock.waitForSleep()

        #expect(ops.isCurrentlyEnabled)
        #expect(ops.setEnabledCalls.isEmpty)
        withExtendedLifetime(source) {}
    }

    /// (a) The system invalidates the mach port outright. Re-enabling can never
    /// revive an invalid port, so the poll must uninstall and reinstall from
    /// scratch — and the reinstalled port must route back to the same source so
    /// its consumer keeps working (suppression survives by construction).
    @Test func pollReinstallsInvalidatedTap() async {
        let (source, ops, clock) = await installedSource()
        let firstToken = ops.currentToken

        ops.simulateSystemInvalidate()

        // Next poll iteration: it finds the port invalid and reinstalls.
        clock.advance()
        await clock.waitForSleep()

        #expect(ops.installCount == 2)
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)
        // A fresh token, not the dead one re-enabled.
        #expect(ops.currentToken !== firstToken)
        // The reinstall pointed the fresh port back at the same source, so its
        // dynamically-read consumer is preserved — never re-enabled, never
        // dropped.
        #expect(ops.setEnabledCalls.isEmpty)
        #expect(ops.installedUserInfos.count == 2)
        #expect(ops.installedUserInfos[0] == ops.installedUserInfos[1])
        withExtendedLifetime(source) {}
    }

    /// (c) An invalidated port reinstalls while permission holds, but once
    /// permission is revoked the poll takes the teardown path and never
    /// reinstalls again — no reinstall loop. The permission gate precedes the
    /// validity check, so a revoked permission tears down regardless of the
    /// port's validity. The first phase (invalidation under grant → one
    /// reinstall) is the load-bearing contrast the revoked phase is measured
    /// against — without it the invalidation would be inert here, the teardown
    /// firing identically on a still-valid port.
    @Test func invalidatedTapUnderRevokedPermissionTearsDownWithoutReinstallLoop() async {
        let permission = MockAccessibilityPermission(granted: true)
        let (source, ops, clock) = await installedSource(permission: permission)

        // Invalidation while permission holds DOES reinstall from scratch — the
        // contrast that makes the revoked-permission behavior below meaningful.
        ops.simulateSystemInvalidate()
        clock.advance()
        await clock.waitForSleep()
        #expect(ops.installCount == 2)
        #expect(ops.isInstalled)

        // Permission is revoked and the fresh port invalidated again: the poll
        // must tear down (permission gone) and never reinstall, even across
        // repeated polls — an invalid port is not a reinstall trigger here.
        permission.granted = false
        ops.simulateSystemInvalidate()
        clock.advance()
        await clock.waitForSleep()
        clock.advance()
        await clock.waitForSleep()

        #expect(!ops.isInstalled)
        #expect(ops.installCount == 2)   // never reinstalled under revocation
        withExtendedLifetime(source) {}
    }

    /// (d) The unlock re-engage path (setConsumer) must detect an invalidated
    /// port too, reinstalling synchronously rather than waiting up to a full
    /// poll interval — the fresh port adopts the consumer just set.
    @Test func reEngageReinstallsInvalidatedTap() async {
        let (source, ops, _) = await installedSource()
        let firstToken = ops.currentToken

        ops.simulateSystemInvalidate()
        source.setConsumer { _, _, _ in true }

        #expect(ops.installCount == 2)
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)
        #expect(ops.currentToken !== firstToken)
        #expect(ops.installedUserInfos.count == 2)
        #expect(ops.installedUserInfos[0] == ops.installedUserInfos[1])
    }
}
