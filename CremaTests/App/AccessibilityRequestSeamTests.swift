import Testing
@testable import Crema

/// The onboarding's one job, in the right order.
///
/// The system prompt is what REGISTERS the app in the Accessibility list; the
/// deep link only takes the user to the pane. Ask first and they find Crema
/// waiting there with a switch. Skip the ask — a mutation deleting it left the
/// whole suite green — and they land on a list the app is not in, with nothing
/// to turn on and no hint why, which is a dead end the app itself created.
@MainActor
struct AccessibilityRequestSeamTests {

    private final class Steps {
        private(set) var order: [String] = []
        func record(_ step: String) { order.append(step) }
    }

    private final class RecordingPermission: AccessibilityPermission, @unchecked Sendable {
        let steps: Steps
        init(_ steps: Steps) { self.steps = steps }
        func isGranted() -> Bool { false }
        func requestAccess() { steps.record("prompt") }
    }

    @Test func theSystemPromptComesBeforeTheSettingsPane() {
        let steps = Steps()
        AppCore.requestAccessibility(RecordingPermission(steps)) { steps.record("settings") }
        #expect(steps.order == ["prompt", "settings"])
    }
}
