import Combine
import SwiftUI
#if !DEBUG
import Sparkle
#endif

/// App-shell wrapper over Sparkle's updater. Auto-update is an app-lifecycle
/// concern, so it lives in the App layer — never in the Coordinator or Sources
/// (which stay ignorant of distribution).
///
/// The Sparkle controller is constructed only in Release: dev builds must never
/// contact the appcast feed, so in Debug this type is an inert shell (no
/// controller, `canCheckForUpdates` stays false) and the "Check for Updates…"
/// menu item does not exist at all (see `CremaApp`). The empty shell keeps the
/// type instantiable in Debug/test builds so its build-config contract can be
/// pinned by a test without ever touching Sparkle.
@MainActor
final class UpdaterModel: ObservableObject {
    /// Whether this build ships the updater (menu item + Sparkle controller).
    /// True only in Release; the compile-time source of truth the menu mirrors.
    static var isSupported: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Mirrors Sparkle's `canCheckForUpdates` so the menu item disables while a
    /// check is already in flight (the published-property pattern). Always false
    /// in Debug, where no controller exists.
    @Published private(set) var canCheckForUpdates = false

    #if !DEBUG
    private let controller: SPUStandardUpdaterController

    init() {
        // Idiomatic modern setup: start the updater immediately, no custom
        // delegates. Consent stays Sparkle's own — we set no
        // SUEnableAutomaticChecks/SUAutomaticallyUpdate defaults, so Sparkle
        // asks on the second launch and installs only on a user click.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents Sparkle's update UI. The caller activates the app first (accessory
    /// apps have no key window, so the panel would otherwise open behind).
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }
    #else
    init() {}

    func checkForUpdates() {}
    #endif
}
