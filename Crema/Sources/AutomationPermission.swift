/// Capability check for the Automation permission (Apple Events) — the
/// prerequisite of the JXA now-playing FALLBACK, never of the adapter path that
/// normally feeds Now Playing. Behind a protocol so the Settings row is testable
/// with a mock; the real implementation asks the Apple Event manager.
///
/// The split between the two calls is the contract, not a convenience: only ONE
/// of them may prompt. A state read is allowed to run on a timer and while a
/// window is merely on screen, so it must never be able to raise a consent
/// dialog — a prompt nobody asked for is a side effect driven by rendering.
protocol AutomationPermission: Sendable {
    /// Reads the current state for one target WITHOUT prompting. Blocking: the
    /// answer comes from another process, so callers hop it off the main thread.
    func state(forBundleID bundleID: String) -> AutomationPermissionState
    /// Asks for one target, prompting when macOS has not decided yet — the
    /// user's explicit click, and nothing else, may reach this. Returns the
    /// resulting state, so a grant needs no second read to be seen.
    func request(forBundleID bundleID: String) -> AutomationPermissionState
}

/// What macOS knows about our permission to automate one app. Three of the five
/// cases are NOT a "no": two are absences of knowledge (nobody has been asked;
/// the app is closed, so there is nothing to be asked about) and one is an answer
/// we could not interpret. Collapsing any of them into `denied` would make the UI
/// accuse the user of a refusal they never made.
enum AutomationPermissionState: Equatable, Sendable {
    case granted
    /// The user said no. Not re-askable — the consent prompt never returns, so
    /// only System Settings can reverse it.
    case denied
    /// macOS has never asked. Askable: the prompt is the whole path to a grant.
    case undecided
    /// The target app is not running (or not installed), and consent is only
    /// answerable about a running app. Says nothing about what the answer will be,
    /// and it is the RESTING state of a machine with no music app open.
    case targetNotRunning
    /// The system answered something we do not map. Reported as unknown rather
    /// than guessed in either direction.
    case unknown

    /// The single state a row can show for a path that needs ANY of its targets:
    /// the JXA fallback reads whichever player is playing, so one granted target
    /// is already a working fallback. Below that the order is what the user can
    /// act on — a real refusal to reverse, then an ask nobody has made, then the
    /// absences. No answers at all is `unknown`, never `granted`.
    static func aggregate(_ answers: [Self]) -> Self {
        if answers.contains(.granted) { return .granted }
        if answers.contains(.denied) { return .denied }
        if answers.contains(.undecided) { return .undecided }
        if answers.contains(.targetNotRunning) { return .targetNotRunning }
        return .unknown
    }
}
