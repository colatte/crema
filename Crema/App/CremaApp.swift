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
            // Everything the menu SAYS — the switch and the style submenu, the
            // status, the warnings, the media — is four blocks decided in one pure
            // place (MenuStatus) and rendered by CremaMenu, so which lines exist, in
            // what order and behind which gate is pinned by tests instead of resting
            // on the shape of this closure. It closes with the separator that
            // divides it from the actions below, which are what remains here: they
            // are unconditional, so there is no gating to pin.
            // (docs/DECISIONS.md: menu-status-before-warnings)
            CremaMenu(core: core)
            #if !DEBUG
            // A fact with its repair under it, so it sits above the actions and not
            // among them. The one line of that shape which does NOT come from
            // MenuStatus, deliberately — the updater exists only in Release and
            // AppCore never holds it, so routing it through that pure type would put
            // a case in it the Debug-hosted suite can never reach. Its whole gate is
            // one mirrored Bool, which is the shape MenuStatus exists to keep out of
            // view bodies in the first place.
            PendingUpdateMenuSection(updater: updater)
            #endif
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
/// Says a scheduled update is waiting and gives the one click that reaches it.
/// Nothing at all when none is pending — the menu keeps the shape it has today.
///
/// The shape is the house rule for a fact with a repair: a plain disabled sentence,
/// no glyph, and the button directly under it, fenced by the separator that closes
/// the block (docs/DECISIONS.md: menu-status-before-warnings). Sparkle already
/// showed its alert for this update — for an accessory app, behind every other
/// running app — so the button does not start a new check; `checkForUpdates()` on an
/// already-presented update is how Sparkle brings that alert back into focus, and
/// the activation is the same one SettingsMenuButton needs for the same reason.
private struct PendingUpdateMenuSection: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        if updater.hasPendingUpdate {
            Text(String(localized: "menu.update.available", defaultValue: "An update to Crema is available."))
            Button(String(localized: "menu.update.show", defaultValue: "Show the Update…")) {
                NSApp.activate()
                updater.checkForUpdates()
            }
            Divider()
        }
    }
}

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
