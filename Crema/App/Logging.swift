import Foundation
import os

extension Logger {
    /// The one place that knows the app's log subsystem (bundle id, with the
    /// fallback for the nil-bundle edge). Categories name the layer or source
    /// ("Coordinator", "NowPlaying", "OSD", "Windows"...), per CLAUDE.md.
    static func crema(_ category: String) -> Logger {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
            category: category
        )
    }
}
