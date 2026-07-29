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
    /// Revocation ALONE, with nothing wrong with the port — the case the test
    /// below cannot see, because there the invalidation reaches the same end
    /// state by the other path (heal → uninstall → install refused). A mutation
    /// deleting the permission check from the poll left the whole suite green.
    ///
    /// What it costs to skip the teardown is not the revocation itself (macOS
    /// stops delivering either way) but the RE-GRANT: `installTapIfAuthorized`
    /// returns early while a token is stored, and the health-check only acts on
    /// an invalid or disabled port — so a stale token that still reads healthy
    /// means the fresh tap is never created and the keys never come back without
    /// a relaunch.
    @Test func revocationTearsDownAHealthyTapSoARegrantCanInstallAFreshOne() async {
        let permission = MockAccessibilityPermission(granted: true)
        let (source, ops, clock) = await installedSource(permission: permission)
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)      // valid port, enabled: nothing to heal

        permission.granted = false
        clock.advance()
        await clock.waitForSleep()

        #expect(!ops.isInstalled)
        #expect(ops.operations.contains("uninstall"))

        // And the state is honest enough for the grant to be actionable again.
        permission.granted = true
        clock.advance()
        await clock.waitForSleep()

        #expect(ops.isInstalled)
        #expect(ops.installCount == 2)
        withExtendedLifetime(source) {}
    }

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

    /// (unlock reinstall) `reinstallTap` forces a brand-new port even when the
    /// current one is healthy — valid AND enabled, the state where the
    /// health-check deliberately no-ops. This is the ENABLED-but-deaf field
    /// failure (valid, enabled, zero events) the two health checks cannot see.
    /// It tears down before installing (paired, no orphan) and the fresh port
    /// routes back to the same source, so the dynamically-read consumer survives.
    @Test func reinstallTapForcesFreshPortEvenWhenHealthy() async {
        let (source, ops, _) = await installedSource()
        source.setConsumer { _, _, _ in true }
        let firstToken = ops.currentToken
        #expect(ops.installCount == 1)
        #expect(ops.isCurrentlyEnabled)   // healthy: a health-check would no-op

        source.reinstallTap()

        #expect(ops.installCount == 2)                 // forced despite a healthy port
        #expect(ops.isInstalled)
        #expect(ops.isCurrentlyEnabled)
        #expect(ops.currentToken !== firstToken)       // a genuinely fresh port
        // Paired teardown: the old port is uninstalled before the fresh install,
        // so no orphan port is left behind.
        #expect(ops.operations == ["install", "uninstall", "install"])
        // A reinstall, never a re-enable — setEnabled is untouched.
        #expect(ops.setEnabledCalls.isEmpty)
        // Same source pointer across the reinstall → the callback reads the same,
        // unchanged consumer: suppression/observation preserved by construction.
        #expect(ops.installedUserInfos.count == 2)
        #expect(ops.installedUserInfos[0] == ops.installedUserInfos[1])
        withExtendedLifetime(source) {}
    }

    /// `reinstallTap` no-ops while the permission is missing: nothing is
    /// installed, and the poll installs the instant permission lands, so there
    /// is nothing to force and no spurious install to leak.
    @Test func reinstallTapNoOpsWithoutPermission() async {
        let ops = FakeEventTapOperating()
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: MockAccessibilityPermission(granted: false),
            clock: clock,
            tapOps: ops
        )
        await clock.waitForSleep()   // first poll: permission missing, nothing installed
        #expect(ops.installCount == 0)

        source.reinstallTap()

        #expect(ops.installCount == 0)
        #expect(!ops.isInstalled)
        withExtendedLifetime(source) {}
    }
}
