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
            // Who is receiving the media keys. Evaluated as the menu is built,
            // like the login-item verdict below: the answer lives outside this
            // process and changes whenever any app installs a tap.
            switch core.mediaKeyChainNotice() {
            case .drawingFromBetterDisplay:
                Text(String(
                    localized: "menu.betterDisplay.drawing",
                    defaultValue: "✓ Screen brightness HUD comes from BetterDisplay"
                ))
                Divider()
            case .betterDisplayAheadAndSilent:
                Text(String(
                    localized: "menu.betterDisplay.silent",
                    defaultValue: "⚠️ BetterDisplay takes the brightness keys — turn on its OSD notification integration and Crema can draw the HUD"
                ))
                Divider()
            case .anotherAppAhead(let app):
                // Stated as the fact it is — a position in the chain, not a
                // malfunction — because from inside the app the symptom is
                // indistinguishable from a broken tap, and no user can diagnose
                // it unaided.
                Text(String(
                    localized: "menu.mediaKeysPrecededBy",
                    defaultValue: "⚠️ \(app) receives the media keys before Crema — some HUDs may not appear"
                ))
                Divider()
            case .quiet:
                EmptyView()
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
            // Evaluated as the menu is built (pull-based, like the suppression
            // warning below): the registration's truth lives on the other side
            // of the system, so it is read where it is shown and never cached.
            switch core.loginItemOutcome() {
            case .revokedByUpdate:
                Text(String(
                    localized: "menu.loginItem.revoked",
                    defaultValue: "⚠️ Open at login was turned off — the app changed since you enabled it"
                ))
                Button(String(
                    localized: "menu.loginItem.reactivate",
                    defaultValue: "Turn it back on"
                )) {
                    core.reactivateLoginItem()
                }
                Divider()
            case .needsApproval:
                Text(String(
                    localized: "menu.loginItem.needsApproval",
                    defaultValue: "⚠️ Open at login is waiting for your approval"
                ))
                Button(String(
                    localized: "menu.loginItem.openSettings",
                    defaultValue: "Open Login Items settings…"
                )) {
                    core.openLoginItemsSettings()
                }
                Divider()
            case .quiet, .userRemoved:
                EmptyView()
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
            Button(String(localized: "menu.quit", defaultValue: "Quit Crema")) {
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
