/// What the Permissions row can offer the user for the Automation state it is
/// showing. Kept apart from the state itself because this is UI policy — and the
/// one place a wrong answer sends someone somewhere useless — and kept pure so a
/// test pins it without a window.
enum AutomationNextStep: Equatable {
    /// Nothing to offer: it is granted, or there is no answer worth acting on.
    case quiet
    /// Offer the consent prompt. `enabled: false` keeps the button VISIBLE and
    /// inert (the macOS dependent-control pattern) for the case where the ask is
    /// real but impossible right now: macOS answers about a RUNNING app only, so
    /// with every music app closed there is nobody to ask about.
    case ask(enabled: Bool)
    /// Only System Settings can reverse this. The consent prompt never comes back
    /// after a refusal, so offering the ask here would be a button that does
    /// nothing.
    case openSettings
}

extension AutomationPermissionState {
    /// The row's one action. `targetNotRunning` and `unknown` deliberately do NOT
    /// send the user to the Automation pane: an app that has never asked for
    /// consent is not listed there, so that button would land on a list Crema is
    /// absent from, with nothing to switch on — the same trap the Accessibility
    /// flow avoids by prompting before it opens its pane.
    var nextStep: AutomationNextStep {
        switch self {
        case .granted, .unknown: .quiet
        case .undecided: .ask(enabled: true)
        case .targetNotRunning: .ask(enabled: false)
        case .denied: .openSettings
        }
    }
}
