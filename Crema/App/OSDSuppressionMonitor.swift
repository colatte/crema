import Observation

/// Observable signal for the menu bar: which suppression domains have failed
/// long enough to be worth telling the user about (A1). The suppressor suspends
/// a failing domain silently and self-heals on a probe; only a domain that
/// stays unrecoverable with its channel present escalates to here. AppCore
/// feeds this from the suppressor's `onSuspensionStateChange`; the menu reads
/// it (pull-based, so a transient suspension that heals before the user opens
/// the menu never shows). Empty is the healthy, invisible default.
@MainActor
@Observable
final class OSDSuppressionMonitor {
    private(set) var longSuspendedDomains: Set<OSDSuppressionDomain> = []

    func update(_ domains: Set<OSDSuppressionDomain>) {
        if domains != longSuspendedDomains { longSuspendedDomains = domains }
    }
}
