import Foundation
import os

extension Logger {
    /// The one place that knows the app's log subsystem (bundle id, with the
    /// fallback for the nil-bundle edge). The category is each call site's: it
    /// names the layer or the Sources/ subfolder it logs from ("Coordinator",
    /// "NowPlaying", "OSD", "Windows"…), and nothing registers the set.
    static func crema(_ category: String) -> Logger {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "com.colatte.crema",
            category: category
        )
    }
}
