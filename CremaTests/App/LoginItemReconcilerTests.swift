import Testing
@testable import Crema

/// The launch-at-login reconciliation (docs/DECISIONS.md: login-item-intent):
/// the registration lives beyond the Background Task Management boundary and
/// macOS revokes it whenever the bundle's code identity changes — proven on
/// hardware, where a morning's boot simply never launched the app and the
/// system logged nothing at all. The intent says what the user asked for; the
/// recorded build says WHO made the registration disappear, which is the whole
/// difference between an honest warning and nagging someone who turned it off
/// themselves.
struct LoginItemReconcilerTests {

    @Test func silentWhenTheUserNeverAsked() {
        // The app never registers uninvited, so it also never has anything to
        // say about a registration that is simply absent.
        for status in [LoginItemStatus.notRegistered, .requiresApproval, .enabled] {
            #expect(LoginItemReconciler.outcome(
                intends: false, recordedBuild: nil, currentBuild: "10200", status: status
            ) == .quiet)
        }
    }

    @Test func silentWhenRealityMatchesTheIntent() {
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: "10200", currentBuild: "10200", status: .enabled
        ) == .quiet)
        // Still silent after an update that kept the registration alive — the
        // build changing is not by itself news.
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: "10200", currentBuild: "10300", status: .enabled
        ) == .quiet)
    }

    @Test func parkedForApprovalIsWorthSaying() {
        // A non-throwing register() can land here, and the only place the user
        // would otherwise notice is the next boot that does not happen.
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: "10200", currentBuild: "10200", status: .requiresApproval
        ) == .needsApproval)
    }

    @Test func aRegistrationLostAcrossBuildsWasRevoked() {
        // The field case: the bundle's identity changed (rebuild, reinstall, or
        // the eventual Developer ID move) and macOS dropped the record without
        // telling anyone.
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: "10200", currentBuild: "10300", status: .notRegistered
        ) == .revokedByUpdate)
    }

    @Test func aRegistrationLostUnderTheSameBuildWasTheUser() {
        // Nothing about the app changed, so the removal came from System
        // Settings — the app forgets the intent instead of insisting.
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: "10200", currentBuild: "10200", status: .notRegistered
        ) == .userRemoved)
    }

    @Test func anIntentWithNoRecordedBuildErrsTowardWarning() {
        // Only reachable by hand-edited defaults: warning once is recoverable,
        // dropping the user's choice in silence is not.
        #expect(LoginItemReconciler.outcome(
            intends: true, recordedBuild: nil, currentBuild: "10200", status: .notRegistered
        ) == .revokedByUpdate)
    }
}

/// The seam that joins the reconciler to the persisted intent — standalone and
/// static in AppCore so it runs without booting the graph. What it must protect
/// above all: no path here ever registers by itself. The user's own click is the
/// only thing allowed to touch the system (docs/DECISIONS.md: login-item-intent).
///
/// The seam is split in three on purpose, and the split is what these tests pin:
/// `loginItemOutcome` is the READ the menu renders from (a view body, rebuilt
/// whenever SwiftUI invalidates it, so it must not write), `reconcileLoginItemIntent`
/// is the launch-edge WRITE that forgets an intent the user revoked themselves,
/// and `applyLaunchesAtLogin` records the intent only on a call that did not
/// throw — the build stamp is the discriminator, and a failed attempt that
/// restamped it would erase the very warning it should preserve
/// (docs/DECISIONS.md: pref-sacred).
@MainActor
struct LoginItemSeamTests {

    private func prefs() -> (Preferences, EphemeralDefaults) {
        let defaults = EphemeralDefaults()
        return (Preferences(defaults: defaults.defaults), defaults)
    }

    @Test func aRevokedRegistrationIsReportedWithoutTouchingTheSystem() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .notRegistered)
        preferences.launchesAtLogin = true
        preferences.launchesAtLoginBuild = "10200"

        let outcome = AppCore.reconcileLoginItemIntent(
            preferences: preferences, status: item.status, currentBuild: "10300"
        )

        #expect(outcome == .revokedByUpdate)
        #expect(item.registerCount == 0)          // reported, never repaired behind the user
        #expect(preferences.launchesAtLogin)      // the intent survives to be acted on
        withExtendedLifetime(defaults) {}
    }

    @Test func anIntentTheUserRevokedIsForgottenQuietly() {
        let (preferences, defaults) = prefs()
        preferences.launchesAtLogin = true
        preferences.launchesAtLoginBuild = "10200"

        let first = AppCore.reconcileLoginItemIntent(
            preferences: preferences, status: .notRegistered, currentBuild: "10200"
        )
        #expect(first == .userRemoved)
        #expect(!preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == nil)

        // And the next evaluation is silent — the warning never becomes a nag.
        let second = AppCore.reconcileLoginItemIntent(
            preferences: preferences, status: .notRegistered, currentBuild: "10200"
        )
        #expect(second == .quiet)
        withExtendedLifetime(defaults) {}
    }

    @Test func theUsersOwnClickIsTheOnlyThingThatRegisters() throws {
        let item = MockLoginItem(status: .notRegistered)
        #expect(item.registerCount == 0)
        try item.setEnabled(true)                 // the menu action / the toggle
        #expect(item.registerCount == 1)
        #expect(item.status == .enabled)
    }

    @Test func theMenusReadNeverWritesTheIntent() {
        let (preferences, defaults) = prefs()
        preferences.launchesAtLogin = true
        preferences.launchesAtLoginBuild = "10200"

        // `.userRemoved` is the one verdict that used to carry a write, and the
        // caller is a view body — the app does not choose when it runs. Read
        // three times on purpose: a write would make the second read `.quiet`.
        for _ in 0..<3 {
            #expect(AppCore.loginItemOutcome(
                preferences: preferences, status: .notRegistered, currentBuild: "10200"
            ) == .userRemoved)
        }
        #expect(preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == "10200")
        withExtendedLifetime(defaults) {}
    }

    @Test func aFailedRegistrationRecordsNoIntent() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .notRegistered)
        item.failOnSet = true

        let result = AppCore.applyLaunchesAtLogin(
            true, to: item, preferences: preferences, currentBuild: "10300"
        )

        #expect(item.registerCount == 1)          // the attempt happened
        #expect(!result.enabled)                  // and the toggle snaps back
        #expect(!preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == nil)
        // The consequence that matters: no intent, so nothing to misread later.
        #expect(AppCore.loginItemOutcome(
            preferences: preferences, status: item.status, currentBuild: "10300"
        ) == .quiet)
        withExtendedLifetime(defaults) {}
    }

    @Test func aFailedRepairKeepsTheRevocationWarningAlive() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .notRegistered)   // macOS dropped the record
        preferences.launchesAtLogin = true
        preferences.launchesAtLoginBuild = "10200"         // enabled under the old build
        #expect(AppCore.loginItemOutcome(
            preferences: preferences, status: item.status, currentBuild: "10300"
        ) == .revokedByUpdate)

        // The one-click repair behind that warning, and it fails.
        item.failOnSet = true
        _ = AppCore.applyLaunchesAtLogin(
            true, to: item, preferences: preferences, currentBuild: "10300"
        )

        // Restamping the build on a failed attempt would make the next reading
        // "gone under the same build" — the user's own request filed away as their
        // own removal, and the warning gone with it.
        #expect(item.registerCount == 1)
        #expect(preferences.launchesAtLoginBuild == "10200")
        #expect(AppCore.loginItemOutcome(
            preferences: preferences, status: item.status, currentBuild: "10300"
        ) == .revokedByUpdate)
        withExtendedLifetime(defaults) {}
    }

    @Test func aFailedDisableKeepsTheIntentItCouldNotUndo() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .enabled)
        preferences.launchesAtLogin = true
        preferences.launchesAtLoginBuild = "10200"
        item.failOnSet = true

        let result = AppCore.applyLaunchesAtLogin(
            false, to: item, preferences: preferences, currentBuild: "10200"
        )

        // The registration is still there, so the toggle stays on and the intent
        // describing it stays recorded: clearing it would leave the app opening at
        // login with no intent left for the reconciler to watch.
        #expect(result.enabled)
        #expect(preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == "10200")
        withExtendedLifetime(defaults) {}
    }

    @Test func aSuccessfulToggleStampsTheBuildAndClearsItAgain() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .notRegistered)

        #expect(AppCore.applyLaunchesAtLogin(
            true, to: item, preferences: preferences, currentBuild: "10300"
        ).enabled)
        #expect(preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == "10300")

        // Turning it off leaves no stamp behind: a stale build would outlive the
        // intent it was recorded for.
        #expect(!AppCore.applyLaunchesAtLogin(
            false, to: item, preferences: preferences, currentBuild: "10400"
        ).enabled)
        #expect(!preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == nil)
        withExtendedLifetime(defaults) {}
    }

    @Test func aRegistrationParkedForApprovalStillRecordsTheIntent() {
        let (preferences, defaults) = prefs()
        let item = MockLoginItem(status: .notRegistered)
        item.enableRequiresApproval = true

        let result = AppCore.applyLaunchesAtLogin(
            true, to: item, preferences: preferences, currentBuild: "10300"
        )

        // The tempting over-correction is to gate the write on the resulting
        // status; BTM can lag the call, and a parked registration is still the
        // user having asked.
        #expect(result.enabled)          // stays on, with the approval footnote
        #expect(result.needsApproval)
        #expect(preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == "10300")
        withExtendedLifetime(defaults) {}
    }
}
