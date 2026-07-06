import AppKit
import SwiftUI

@main
struct CremaApp: App {
    @State private var core = AppCore()

    var body: some Scene {
        MenuBarExtra(
            String(localized: "app.menubar.title", defaultValue: "Crema"),
            systemImage: "capsule"
        ) {
            if !core.permissionMonitor.isGranted {
                Text(String(
                    localized: "menu.accessibilityWarning",
                    defaultValue: "⚠️ Accessibility permission missing — media keys are not captured"
                ))
                Button(String(localized: "menu.grantAccessibility", defaultValue: "Grant Accessibility Access…")) {
                    core.presentAccessibilityOnboarding()
                }
                Divider()
            }
            if !core.nowPlayingMonitor.isActive {
                Text(String(
                    localized: "menu.nowPlayingUnavailable",
                    defaultValue: "⚠️ Now Playing unavailable — no media source"
                ))
                Divider()
            }
            if !core.coordinator.commandsAvailable {
                Text(String(
                    localized: "menu.mediaControlsBlocked",
                    defaultValue: "⚠️ Media controls blocked by macOS — showing playback only"
                ))
                Divider()
            }
            SettingsMenuButton()
            Divider()
            #if DEBUG
            DemoMenu(core: core)
            Divider()
            #endif
            Button(String(localized: "menu.quit", defaultValue: "Quit")) {
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
/// or the Preferences window would open behind whatever is frontmost.
private struct SettingsMenuButton: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button(String(localized: "menu.settings", defaultValue: "Settings…")) {
            NSApp.activate(ignoringOtherApps: true)
            openSettings()
        }
        .keyboardShortcut(",")
    }
}
