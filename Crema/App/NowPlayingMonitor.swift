import Observation

/// Observable signal for whether a now-playing source is active, so the menu
/// bar can show the degraded state when the whole chain is off. The chain
/// updates it (hopping to the main actor); the demo path leaves it true.
@MainActor
@Observable
final class NowPlayingMonitor {
    private(set) var isActive = true

    func setActive(_ active: Bool) {
        if active != isActive { isActive = active }
    }
}
