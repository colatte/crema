import Foundation
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

    /// The other half of that stand-down, and the one the entry guard cannot cover:
    /// a read that was ALREADY off the actor when the click landed is past the
    /// guard, and its answer is the pre-decision one by construction. Merged
    /// last-writer-wins on the way back, it takes the user's grant off the screen.
    @Test func aReadAlreadyInFlightWhenTheDialogIsAnsweredCannotUndoTheGrant() async {
        let permission = ParkedReadPermission(reads: .undecided, answersTheDialog: .granted)
        let monitor = AutomationPermissionMonitor(permission: permission, targets: [music], clock: TestSleepClock())
        // The first read is what makes the target askable at all: the prompt goes
        // only to targets recorded as undecided.
        await monitor.refresh()
        #expect(monitor.state == .undecided)

        permission.holdReads()
        let inFlight = Task { await monitor.refresh() }
        #expect(await eventually { permission.readCount == 2 })

        await monitor.askForConsent()
        #expect(monitor.state == .granted)

        permission.releaseReads()
        await inFlight.value
        #expect(monitor.state == .granted)
    }

    /// Parks the NON-prompting read, which the shared mock cannot do — it parks
    /// prompts, and the window above needs a read held open ACROSS an ask that
    /// starts and finishes. Local to this suite for that reason.
    private final class ParkedReadPermission: AutomationPermission, @unchecked Sendable {
        private let lock = NSLock()
        /// Separate from `lock`, like the shared mock's: a parked read must not hold
        /// the lock the counter accessor needs, or the test could not observe the
        /// read it is waiting on.
        private let gate = NSCondition()
        private let readAnswer: AutomationPermissionState
        private let dialogAnswer: AutomationPermissionState
        private var _readCount = 0
        private var holdingReads = false

        init(reads readAnswer: AutomationPermissionState, answersTheDialog dialogAnswer: AutomationPermissionState) {
            self.readAnswer = readAnswer
            self.dialogAnswer = dialogAnswer
        }

        var readCount: Int { lock.withLock { _readCount } }

        func holdReads() {
            gate.lock()
            holdingReads = true
            gate.unlock()
        }

        func releaseReads() {
            gate.lock()
            holdingReads = false
            gate.broadcast()
            gate.unlock()
        }

        func state(forBundleID bundleID: String) -> AutomationPermissionState {
            lock.withLock { _readCount += 1 }
            // Wall-clock bounded, like every wait in this suite: a test that forgets
            // to release fails loud downstream instead of hanging.
            let deadline = Date().addingTimeInterval(boundedWaitSeconds)
            gate.lock()
            while holdingReads, Date() < deadline {
                _ = gate.wait(until: deadline)
            }
            gate.unlock()
            return readAnswer
        }

        func request(forBundleID bundleID: String) -> AutomationPermissionState { dialogAnswer }
    }
}
