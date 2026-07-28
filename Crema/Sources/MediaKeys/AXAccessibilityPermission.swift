import ApplicationServices

/// Real Accessibility permission over the AX API.
struct AXAccessibilityPermission: AccessibilityPermission {
    func isGranted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt and registers the app in System Settings →
    /// Privacy & Security → Accessibility, so the user finds it pre-listed.
    func requestAccess() {
        // The literal stands in for kAXTrustedCheckOptionPrompt: the SDK leaves
        // that C global without concurrency annotations, so Swift 6 rejects any
        // reference to it; the key's documented value is this stable string.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
