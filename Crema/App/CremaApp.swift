import AppKit
import SwiftUI

/// The app. Launched by `CremaMain`, which keeps the unit-test host from
/// running it.
struct CremaApp: App {
    @NSApplicationDelegateAdaptor(CremaAppDelegate.self) private var lifecycle
    @State private var core = AppCore()
    #if !DEBUG
    // Constructed only in Release: the updater must never exist in dev builds,
    // so the whole property (and its SPUStandardUpdaterController) is compiled out.
    @StateObject private var updater = UpdaterModel()
    #endif

    var body: some Scene {
        // The status icon is the app's identity, not the generic SF capsule:
        // a TEMPLATE image (the system tints it for dark/light/accent) of the
        // app icon's mark, generated at @1x/@2x by
        // design/icon/makemenubaricon.swift — regenerate there, never edit
        // the PNGs by hand.
        MenuBarExtra(
            String(localized: "app.menubar.title", defaultValue: "Crema"),
            image: "MenuBarIcon"
        ) {
            // Everything the menu SAYS — the switch and the style submenu with their
            // facts, the warnings, the media — is sections decided in one pure place
            // (MenuStatus) and rendered by CremaMenu, so which lines exist, in what
            // order and behind which gate is pinned by tests instead of resting on
            // the shape of this closure. The app's own actions are what remains
            // here: they are unconditional, so there is no gating to pin. Every group
            // is a Section and none is fenced by a Divider, which would double the
            // section's own separator (docs/DECISIONS.md: menu-status-before-warnings).
            CremaMenu(core: core)
            #if !DEBUG
            // A fact with its repair under it, so it sits above the actions and not
            // among them. The one line of that shape which does NOT come from
            // MenuStatus, deliberately — the updater exists only in Release and
            // AppCore never holds it, so routing it through that pure type would put
            // a case in it the Debug-hosted suite can never reach. Its whole gate is
            // one mirrored Bool, which is the shape MenuStatus exists to keep out of
            // view bodies in the first place.
            PendingUpdateMenuSection(updater: updater, core: core)
            #endif
            // Untitled, like every app's own commands at the foot of a menu: the
            // items name themselves, and a heading over them would only repeat the
            // app's name.
            Section {
                SettingsMenuButton(core: core)
                // The tour's way back, where Settings is: the HIG asks that a tour
                // a person skipped or finished stay easy to find (Onboarding).
                Button(String(localized: "menu.welcomeTour", defaultValue: "Welcome Tour…")) {
                    core.showWelcomeTour()
                }
                #if !DEBUG
                // Release-only: in Debug the item does not exist, matching a build
                // that never constructs the updater nor contacts the feed.
                UpdaterMenuButton(updater: updater, core: core)
                #endif
            }
            #if DEBUG
            Section {
                DemoMenu(core: core)
            }
            #endif
            Section {
                Button(String(localized: "menu.quit", defaultValue: "Quit Crema")) {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }

        Settings {
            SettingsView(core: core)
        }
    }
}

/// Opens the Settings window with the standard ⌘, shortcut, brought forward
/// first (`AppCore.bringForward`): with no Dock tile and no app menu, a window
/// that opens behind whatever is frontmost is a window the user cannot reach.
private struct SettingsMenuButton: View {
    let core: AppCore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(String(localized: "menu.settings", defaultValue: "Settings…")) {
            core.bringForward()
            openSettings()
        }
        .keyboardShortcut(",")
    }
}

#if !DEBUG
/// Says a scheduled update is waiting and gives the one click that reaches it.
/// Nothing at all when none is pending — the menu keeps its shape without it.
///
/// The shape is the house rule for a fact with a repair: the button is the item and
/// the fact is its note, in a section of its own
/// (docs/DECISIONS.md: menu-status-before-warnings). Sparkle already
/// showed its alert for this update — for an accessory app, behind every other
/// running app — so the button does not start a new check; `checkForUpdates()` on an
/// already-presented update is how Sparkle brings that alert back into focus, and
/// the app comes forward for the same reason SettingsMenuButton does.
private struct PendingUpdateMenuSection: View {
    @ObservedObject var updater: UpdaterModel
    let core: AppCore

    var body: some View {
        if updater.hasPendingUpdate {
            Section {
                MenuItemNote.item(
                    String(localized: "menu.update.show", defaultValue: "Show Update…"),
                    note: String(localized: "menu.update.available", defaultValue: "An update to Crema is available")
                ) {
                    core.bringForward()
                    updater.checkForUpdates()
                }
            }
        }
    }
}

/// Triggers Sparkle's update check. Like SettingsMenuButton it brings the app
/// forward first — an accessory (LSUIElement) app has no key window, so Sparkle's
/// panel would otherwise open behind whatever is frontmost. Disabled while a check
/// is already in flight (Sparkle's canCheckForUpdates).
private struct UpdaterMenuButton: View {
    @ObservedObject var updater: UpdaterModel
    let core: AppCore

    var body: some View {
        Button(String(localized: "menu.checkForUpdates", defaultValue: "Check for Updates…")) {
            core.bringForward()
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
#endif
