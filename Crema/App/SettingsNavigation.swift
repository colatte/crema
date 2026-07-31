import Observation

/// Where the Settings window should land when something else opens it.
///
/// A mirror in the app's own idiom rather than state on AppCore, which is not
/// observable: the window is a SwiftUI scene and the request has to invalidate
/// its body. Nil is the ordinary case — the window opens on whatever tab it was
/// left on, which is what ⌘, and the menu's Settings item do.
///
/// Consumed once and cleared by the reader, so a request is a one-shot event and
/// not a mode: leaving it set would drag the window back to the same tab every
/// time the user switched away from it.
@MainActor
@Observable
final class SettingsNavigation {
    private(set) var requestedTab: SettingsTab?

    /// A warning offering its own fix: it opens the window AND names where the fix
    /// is, instead of describing the walk. Set before the window is asked to open,
    /// so the tab is already chosen when the scene evaluates.
    func request(_ tab: SettingsTab) {
        requestedTab = tab
    }

    func consume() {
        requestedTab = nil
    }
}

/// The tabs, named where both the window and whoever steers it can see them.
/// The raw values are the DEBUG initial-tab flag's vocabulary and the persisted
/// spelling; renaming one is a user-visible change to that harness.
enum SettingsTab: String {
    case general, nowPlaying, indicators, permissions, about
}
