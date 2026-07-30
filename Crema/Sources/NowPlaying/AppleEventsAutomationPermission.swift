import CoreServices

/// Real Automation permission over the Apple Event manager, for the players the
/// JXA fallback scripts.
///
/// `AEDeterminePermissionToAutomateTarget` is the only way to learn this state
/// without sending an event: with `askUserIfNeeded: false` it answers from the
/// consent database and cannot prompt — measured against a target macOS had never
/// decided about, it returns `errAEEventWouldRequireUserConsent` (-1744) and no
/// dialog appears. Wildcard class/ID asks about the target as a whole, which is
/// the granularity consent is stored at anyway; the bundle ID is matched
/// case-insensitively (also measured), so only a WRONG id fails, never a typo in
/// case.
///
/// Two of its answers are absences rather than denials, and the app depends on
/// the difference: the target must be RUNNING or it answers `procNotFound` (-600,
/// a closed or uninstalled player tells us nothing), and consent macOS has never
/// asked about comes back as the consent-required status. Only -1743 is a refusal.
///
/// Both entry points are synchronous and blocking on purpose — the SDK says not
/// to call this on the main thread, because the prompting form returns only when
/// the user answers the dialog — so callers run them off it (`blockingCall`).
///
/// Whose consent this is matters: the JXA events are sent by a spawned
/// `osascript`, and macOS attributes them to the RESPONSIBLE process, which is
/// Crema — the same subject this call asks about. Probed from the other side: a
/// child process asking this question gets its PARENT's grant back, which is the
/// attribution the fallback relies on. If it ever changed, this row would report a
/// state unrelated to the fallback's real luck.
struct AppleEventsAutomationPermission: AutomationPermission {
    func state(forBundleID bundleID: String) -> AutomationPermissionState {
        determine(bundleID, askUserIfNeeded: false)
    }

    func request(forBundleID bundleID: String) -> AutomationPermissionState {
        determine(bundleID, askUserIfNeeded: true)
    }

    private func determine(_ bundleID: String, askUserIfNeeded: Bool) -> AutomationPermissionState {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        let created = bytes.withUnsafeBufferPointer { buffer in
            AECreateDesc(typeApplicationBundleID, buffer.baseAddress, buffer.count, &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }

        switch AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, askUserIfNeeded) {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .undecided
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .unknown
        }
    }
}
