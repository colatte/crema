import AppKit

/// The Automation (Apple Events) intents the Permissions row calls. They live in
/// an extension, not in the class body, because AppCore's body is already at the
/// type-length ceiling the composition root has earned — every new wire pushes it
/// over, and the graph it wires is what belongs in there.
extension AppCore {
    /// Starts/stops the Automation poll with the Permissions tab. Scoped to the
    /// tab on purpose: the read costs a blocking round trip per app and answers a
    /// question only that row asks. Idempotent on both ends, so a lifecycle edge
    /// SwiftUI delivers twice — or never delivers on close — costs at most the one
    /// poll the user is looking at.
    func watchAutomationPermission(_ watching: Bool) {
        if watching { automationMonitor.start() } else { automationMonitor.stop() }
    }

    /// The user's explicit ask — the only path allowed to prompt. Unlike
    /// Accessibility, the prompt itself is what grants this, so there is no pane to
    /// open afterwards: macOS shows its own dialog and the answer comes back with
    /// it. A target already refused is not re-askable, which is what
    /// `openAutomationSettings()` is for.
    func requestAutomationAccess() {
        Task { await automationMonitor.askForConsent() }
    }

    /// Deep-links to the pane that owns a refusal — the consent prompt never comes
    /// back once the user has said no, so this is the only way back.
    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
