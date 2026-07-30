import Testing
@testable import Crema

/// The Automation state behind a protocol: how the app LEARNS it (never by
/// asking), what the user's click asks for, and what the row has before any
/// answer exists. Polling runs on the injectable clock — no real sleeps, and no
/// system API.
@MainActor
struct AutomationPermissionMonitorTests {
    private let spotify = "com.spotify.client"
    private let music = "com.apple.Music"

    @Test func hasNothingToSayBeforeTheFirstAnswerLands() {
        let monitor = AutomationPermissionMonitor(
            permission: MockAutomationPermission(),
            clock: TestSleepClock()
        )
        #expect(monitor.state == nil)
    }

    @Test func learningTheStateNeverPromptsTheUser() async {
        let permission = MockAutomationPermission([spotify: .undecided, music: .undecided])
        let monitor = AutomationPermissionMonitor(
            permission: permission,
            targets: [spotify, music],
            clock: TestSleepClock()
        )

        await monitor.refresh()

        #expect(monitor.state == .undecided)
        #expect(permission.reads == [spotify, music])
        #expect(permission.prompts.isEmpty)
    }

    @Test func theAskGoesOnlyToTheTargetsMacOSHasNotDecidedAbout() async {
        let permission = MockAutomationPermission([spotify: .denied, music: .undecided])
        let monitor = AutomationPermissionMonitor(
            permission: permission,
            targets: [spotify, music],
            clock: TestSleepClock()
        )
        await monitor.refresh()

        await monitor.askForConsent()

        #expect(permission.prompts == [music])
    }

    @Test func oneGrantedPlayerIsAWorkingFallback() async {
        let permission = MockAutomationPermission([spotify: .granted, music: .denied])
        let monitor = AutomationPermissionMonitor(
            permission: permission,
            targets: [spotify, music],
            clock: TestSleepClock()
        )

        await monitor.refresh()

        #expect(monitor.state == .granted)
    }

    @Test func aGrantMadeInSystemSettingsIsPickedUpWithoutReopeningTheWindow() async {
        let permission = MockAutomationPermission([music: .denied])
        let clock = TestSleepClock()
        let monitor = AutomationPermissionMonitor(permission: permission, targets: [music], clock: clock)
        monitor.start()
        #expect(await eventually { monitor.state == .denied })

        permission.set(.granted, for: music)
        await clock.waitForSleep()
        clock.advance()

        #expect(await eventually { monitor.state == .granted })
        monitor.stop()
    }

    /// Stopping has to CANCEL the poll, not just forget it: a task that keeps its
    /// parked sleep wakes on the next interval and reads again with the tab gone.
    /// Pinned on the clock's own cancellation count, which the cancellation handler
    /// bumps synchronously inside `cancel()` — so this cannot pass by racing.
    @Test func stoppingCancelsThePollSoNothingIsReadWithTheTabAway() async {
        let permission = MockAutomationPermission([music: .denied])
        let clock = TestSleepClock()
        let monitor = AutomationPermissionMonitor(permission: permission, targets: [music], clock: clock)
        monitor.start()
        await clock.waitForSleep()
        let readsWhileWatching = permission.reads.count
        #expect(readsWhileWatching >= 1)

        monitor.stop()

        #expect(clock.cancelledCount == 1)
        #expect(clock.pendingSleeps == 0)
        clock.advance()
        await settle()
        #expect(permission.reads.count == readsWhileWatching)
    }

    @Test func aSecondClickWhileTheDialogIsUpDoesNotStackAnotherOne() async {
        let permission = MockAutomationPermission([music: .undecided])
        let monitor = AutomationPermissionMonitor(permission: permission, targets: [music], clock: TestSleepClock())
        await monitor.refresh()
        permission.holdPrompts()

        let firstClick = Task { await monitor.askForConsent() }
        #expect(await eventually { permission.prompts.count == 1 })
        await monitor.askForConsent()
        #expect(permission.prompts.count == 1)

        permission.releasePrompts()
        await firstClick.value
    }

    /// The poll must stand down while the dialog is up: its answer is the
    /// pre-decision one by construction, and it merges last-writer-wins, so it
    /// would land after the decision and undo the grant on screen.
    @Test func thePollStandsDownWhileTheConsentDialogIsUp() async {
        let permission = MockAutomationPermission([music: .undecided])
        let monitor = AutomationPermissionMonitor(permission: permission, targets: [music], clock: TestSleepClock())
        await monitor.refresh()
        permission.holdPrompts()

        let firstClick = Task { await monitor.askForConsent() }
        #expect(await eventually { permission.prompts.count == 1 })
        let readsBeforeTheDialog = permission.reads.count
        await monitor.refresh()
        #expect(permission.reads.count == readsBeforeTheDialog)

        permission.set(.granted, for: music)
        permission.releasePrompts()
        await firstClick.value
        #expect(monitor.state == .granted)
    }
}
