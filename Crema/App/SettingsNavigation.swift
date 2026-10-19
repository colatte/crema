import Foundation
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
/// The raw values are the DEBUG initial-tab flag's vocabulary and nothing else's
/// (no tab is persisted); renaming one changes that harness, and a name no case
/// matches parses to nil and lands on General.
enum SettingsTab: String {
    case general, nowPlaying, indicators, permissions, about
}

#if DEBUG
extension SettingsTab {
    /// Screenshot/dev harness: `-CremaSettingsInitialTab about` decides the tab
    /// the Settings window LANDS on when it opens. The app's own opens go through
    /// `openSettings` (SwiftUI's OpenSettingsAction, macOS 14), from the menu, and
    /// the ones that name a tab steer it with `settingsNavigation`, which wins over
    /// this flag. An unknown name parses to nil and lands on General silently,
    /// which is the harness's contract: it steers a screenshot run, so a stale
    /// flag is worth a wrong tab and never a crash.
    static var harnessInitial: SettingsTab? {
        UserDefaults.standard.string(forKey: "CremaSettingsInitialTab").flatMap(Self.init(rawValue:))
    }
}
#endif
