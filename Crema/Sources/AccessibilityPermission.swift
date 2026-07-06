/// Capability check for the Accessibility permission (the event tap's
/// prerequisite). Behind a protocol so degradation logic is testable with a
/// mock; the real implementation asks the AX API.
protocol AccessibilityPermission: Sendable {
    /// Re-reads the current state — cheap and callable repeatedly (polled to
    /// detect a grant without relaunching).
    func isGranted() -> Bool
    /// Shows the system prompt and registers the app in the Accessibility
    /// list, so the user finds it pre-listed in System Settings.
    func requestAccess()
}
