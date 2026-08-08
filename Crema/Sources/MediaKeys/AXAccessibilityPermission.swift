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
        // reference to it. Apple documents the SYMBOL and never its value, so
        // this literal is MEASURED from the running framework rather than read
        // off a reference page — the comment used to call it "the key's
        // documented value", which promised a source that does not exist.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
