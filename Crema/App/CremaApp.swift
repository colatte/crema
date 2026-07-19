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
            let suspended = core.osdSuppressionMonitor.longSuspendedDomains
            if !suspended.isEmpty {
                Text(osdSuspendedWarning(suspended))
                Button(String(
                    localized: "menu.osdSuspended.retry",
                    defaultValue: "Try to reactivate now"
                )) {
                    core.retryOSDSuppression()
                }
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
            Button(String(localized: "menu.quit", defaultValue: "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(core: core)
        }
    }

    /// The menu line naming the domains whose native OSD is back. The names are
    /// joined with a locale-aware list format (", " vs " e " vs " and ") in a
    /// stable, enum-declared order.
    private func osdSuspendedWarning(_ domains: Set<OSDSuppressionDomain>) -> String {
        let names = OSDSuppressionDomain.allCases
            .filter(domains.contains)
            .map(localizedDomainName)
            .formatted(.list(type: .and))
        return String(
            localized: "menu.osdSuspended.warning",
            defaultValue: "⚠️ System HUD restored for \(names) — Crema couldn't apply the change"
        )
    }

    private func localizedDomainName(_ domain: OSDSuppressionDomain) -> String {
        switch domain {
        case .volume:
            String(localized: "osd.domain.volume", defaultValue: "Volume")
        case .screenBrightness:
            String(localized: "osd.domain.screenBrightness", defaultValue: "Screen brightness")
        case .keyboardBrightness:
            String(localized: "osd.domain.keyboardBrightness", defaultValue: "Keyboard brightness")
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

#if !DEBUG
/// Triggers Sparkle's update check. Like SettingsMenuButton it activates the app
/// first — an accessory (LSUIElement) app has no key window, so Sparkle's panel
/// would otherwise open behind whatever is frontmost. Disabled while a check is
/// already in flight (Sparkle's canCheckForUpdates).
private struct UpdaterMenuButton: View {
    @ObservedObject var updater: UpdaterModel

    var body: some View {
        Button(String(localized: "menu.checkForUpdates", defaultValue: "Check for Updates…")) {
            NSApp.activate(ignoringOtherApps: true)
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
#endif
