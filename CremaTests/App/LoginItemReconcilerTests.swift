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

        let outcome = AppCore.evaluateLoginItem(
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

        let first = AppCore.evaluateLoginItem(
            preferences: preferences, status: .notRegistered, currentBuild: "10200"
        )
        #expect(first == .userRemoved)
        #expect(!preferences.launchesAtLogin)
        #expect(preferences.launchesAtLoginBuild == nil)

        // And the next evaluation is silent — the warning never becomes a nag.
        let second = AppCore.evaluateLoginItem(
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
}
