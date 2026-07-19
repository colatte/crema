import Testing
@testable import Crema

/// Tap-health self-heal: the case the Stage-1 lock tests could not see — a tap
/// the system disabled behind the source's back (secure-input transitions on
/// the lock screen, timeouts) with no delivered callback. Left unrevived, the
/// tap stays dead while our state says "installed", so keys reach the system
/// and the native OSD comes back alongside ours (double HUD). The poll and the
/// re-engage path both revive it.
struct CGEventTapMediaKeySourceHealthTests {

    /// Drives the poll to the point where the tap is installed and parked on the
    /// interval sleep, then returns everything the test needs.
    private func installedSource() async -> (CGEventTapMediaKeySource, FakeEventTapOperating, TestSleepClock) {
        let ops = FakeEventTapOperating()
        let clock = TestSleepClock()
        let source = CGEventTapMediaKeySource(
            permission: MockAccessibilityPermission(granted: true),
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
}
