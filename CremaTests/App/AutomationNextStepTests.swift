import Testing
@testable import Crema

/// What the Permissions row offers for each state, and what the aggregate over
/// players may claim. The states that mean "no answer" must not send the user
/// anywhere: an app that has never asked for consent is not listed in the
/// Automation pane, so a button that opens it lands on a list Crema is absent
/// from — and no absence of an answer may ever be reported as a refusal.
struct AutomationNextStepTests {

    @Test func aRefusalCanOnlyBeReversedInSystemSettings() {
        #expect(AutomationPermissionState.denied.nextStep == .openSettings)
    }

    @Test func aConsentNobodyHasAskedForIsAskable() {
        #expect(AutomationPermissionState.undecided.nextStep == .ask(enabled: true))
    }

    @Test func withNoMusicAppOpenTheAskStaysVisibleAndInert() {
        #expect(AutomationPermissionState.targetNotRunning.nextStep == .ask(enabled: false))
    }

    @Test func nothingIsOfferedForAGrantOrAnUninterpretableAnswer() {
        #expect(AutomationPermissionState.granted.nextStep == .quiet)
        #expect(AutomationPermissionState.unknown.nextStep == .quiet)
    }

    @Test func anAbsenceOfAnswersIsNeverAGrantAndNeverARefusal() {
        #expect(AutomationPermissionState.aggregate([]) == .unknown)
        #expect(AutomationPermissionState.aggregate([.targetNotRunning, .targetNotRunning]) == .targetNotRunning)
    }

    @Test func aRefusalOutranksATargetNobodyHasAskedAbout() {
        #expect(AutomationPermissionState.aggregate([.undecided, .denied]) == .denied)
    }

    @Test func oneGrantedTargetOutranksEveryOtherAnswer() {
        #expect(AutomationPermissionState.aggregate([.denied, .undecided, .granted]) == .granted)
    }
}
