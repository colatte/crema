import ApplicationServices

/// Real Accessibility permission over the AX API.
struct AXAccessibilityPermission: AccessibilityPermission {
    func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt and registers the app in System Settings →
    /// Privacy & Security → Accessibility, so the user finds it pre-listed.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
