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
        // this literal is MEASURED from the SDK's symbol rather than read off a
        // reference page: scripts/probes/ax-prompt-key.swift, 2026-10-15, macOS
        // 27.0.1; invalidated by a run of that probe printing another value.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
