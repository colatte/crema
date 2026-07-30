import AppKit
import SwiftUI

@main
struct CremaApp: App {
    @State private var core = AppCore()
    #if !DEBUG
    // Constructed only in Release: the updater must never exist in dev builds,
    // so the whole property (and its SPUStandardUpdaterController) is compiled out.
    @StateObject private var updater = UpdaterModel()
    #endif

    var body: some Scene {
        // The status icon is the app's identity, not the generic SF capsule:
        // a TEMPLATE image (the system tints it for dark/light/accent) of the
        // pill silhouette with the crema line, generated at @1x/@2x by
        // design/icon/makemenubaricon.swift — regenerate there, never edit
        // the PNGs by hand.
        MenuBarExtra(
            String(localized: "app.menubar.title", defaultValue: "Crema"),
            image: "MenuBarIcon"
        ) {
            // Information first, actions last: what Crema IS doing, then what needs
            // attention. Which lines exist, in what order, and behind which gate is
            // decided in one pure place (MenuStatus) so it is pinned by tests
            // instead of resting on the shape of this closure; the block closes with
            // the separator that divides it from the actions below.
            // (docs/DECISIONS.md: menu-status-before-warnings)
            MenuInformation(core: core)
            // Gated on the chain being alive: with no media source at all the
            // warning inside the block above already tells that story, and four grey
            // rows that can never work are noise, not a disabled control the user
            // can wait on. Reads the one observable the scene body already read
            // before this round, so the expensive block above rebuilds no more often
            // than it did.
            if core.nowPlayingMonitor.isActive {
                NowPlayingMenuSection(coordinator: core.coordinator)
                Divider()
            }
            SettingsMenuButton()
            #if !DEBUG
            // Release-only: in Debug the item does not exist, matching a build
            // that never constructs the updater nor contacts the feed.
            UpdaterMenuButton(updater: updater)
            #endif
            Divider()
            #if DEBUG
            DemoMenu(core: core)
            Divider()
            #endif
            Button(String(localized: "menu.quit", defaultValue: "Quit Crema")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(core: core)
        }
    }
}

/// Opens the Settings window with the standard ⌘, shortcut. As an accessory
/// (LSUIElement) app Crema has no regular windows, so it must activate itself
/// or the Preferences window would open behind whatever is frontmost — and with
/// no Dock tile and no app menu, a window that opens behind is a window the user
/// cannot reach.
///
/// `activate()`, never `activate(ignoringOtherApps:)`: the SDK marks that
/// selector API_DEPRECATED and names this replacement, available at this app's
/// own deployment target (macOS 14). Nothing warns about the old one — the
/// deprecation is spelled API_TO_BE_DEPRECATED, so the compiler stays quiet
/// while the call rots. Neither form is a guarantee under cooperative
/// activation, which is why the windows still order themselves front.
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(String(localized: "menu.settings", defaultValue: "Settings…")) {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

#if !DEBUG
/// Triggers Sparkle's update check. Like SettingsMenuButton it activates the app
/// first — an accessory (LSUIElement) app has no key window, so Sparkle's panel
/// would otherwise open behind whatever is frontmost. Disabled while a check is
/// already in flight (Sparkle's canCheckForUpdates).
private struct UpdaterMenuButton: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button(String(localized: "menu.checkForUpdates", defaultValue: "Check for Updates…")) {
            NSApp.activate()
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
#endif
