import SwiftUI

/// The Preferences window: a native macOS tabbed Settings scene. Each tab is a
/// grouped Form. Every control binds to the same persisted key the behavior
/// already reads (via @AppStorage) and applies its change live through an
/// AppCore method on change — so nothing here duplicates a preference or needs
/// a relaunch.
@MainActor
struct SettingsView: View {
    let core: AppCore

    var body: some View {
        TabView {
            GeneralSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.general", defaultValue: "General"), systemImage: "gearshape") }
            NowPlayingSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.nowPlaying", defaultValue: "Now Playing"), systemImage: "music.note") }
            SystemHUDSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.systemHUD", defaultValue: "System HUD"), systemImage: "slider.horizontal.3") }
            PermissionsSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.permissions", defaultValue: "Permissions"), systemImage: "lock.shield") }
        }
        .frame(width: 500)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    let core: AppCore
    @State private var style: Style
    /// Mirrors the real login-item status (enabled or pending approval), and is
    /// re-read from it after every attempt — the toggle is a view onto reality,
    /// never a wish that outran it.
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool

    init(core: AppCore) {
        self.core = core
        _style = State(initialValue: core.currentStyle())
        _launchesAtLogin = State(initialValue: core.loginItem.isEnabled || core.loginItem.requiresApproval)
        _loginNeedsApproval = State(initialValue: core.loginItem.requiresApproval)
    }

    var body: some View {
        Form {
            Section {
                Picker(selection: $style) {
                    ForEach(Style.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                } label: {
                    Text(String(localized: "settings.general.style", defaultValue: "Style"))
                }
                .onChange(of: style) { _, new in core.setStyleEverywhere(new) }
            } footer: {
                Text(String(
                    localized: "settings.general.style.footer",
                    defaultValue: "Applies to every display. On a display without a notch, the Notch style falls back to Card."
                ))
                .settingsFootnote()
            }

            Section {
                // A custom binding (not onChange): the setter applies the change
                // and then reflects the real status, so a throw snaps it back and
                // a "requires approval" result keeps it on with the note below —
                // and mutating state in the setter can't re-fire itself.
                Toggle(isOn: Binding(
                    get: { launchesAtLogin },
                    set: { wanted in
                        try? core.loginItem.setEnabled(wanted)
                        launchesAtLogin = core.loginItem.isEnabled || core.loginItem.requiresApproval
                        loginNeedsApproval = core.loginItem.requiresApproval
                    }
                )) {
                    Text(String(localized: "settings.general.launchAtLogin", defaultValue: "Open Crema at login"))
                }
            } footer: {
                if loginNeedsApproval {
                    Text(String(
                        localized: "settings.general.launchAtLogin.needsApproval",
                        defaultValue: "Approve Crema in System Settings › General › Login Items to finish enabling this."
                    ))
                    .foregroundStyle(.orange)
                    .settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Now Playing

private struct NowPlayingSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.reactiveNowPlayingKey) private var reactive = true
    @AppStorage(Preferences.showsPlaybackControlsKey) private var showsControls = true
    @AppStorage(Preferences.includesBrowserMediaKey) private var includesBrowsers = false

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $reactive) {
                    Text(String(localized: "settings.nowPlaying.reactive", defaultValue: "Show on media events"))
                }
                .onChange(of: reactive) { _, new in core.setReactiveNowPlaying(new) }
            } footer: {
                Text(String(
                    localized: "settings.nowPlaying.reactive.footer",
                    defaultValue: "The player appears on its own when a track changes or playback starts. Turn off to keep it hidden until you open it."
                ))
                .settingsFootnote()
            }

            Section {
                Toggle(isOn: $showsControls) {
                    Text(String(localized: "settings.nowPlaying.controls", defaultValue: "Show playback controls"))
                }
                .onChange(of: showsControls) { _, new in core.setShowsPlaybackControls(new) }
            } footer: {
                Text(String(
                    localized: "settings.nowPlaying.controls.footer",
                    defaultValue: "Off shows a view-only player — cover, title, and scrubber, without the transport buttons."
                ))
                .settingsFootnote()
            }

            Section {
                Toggle(isOn: $includesBrowsers) {
                    Text(String(localized: "settings.nowPlaying.browsers", defaultValue: "Include browser media"))
                }
                .onChange(of: includesBrowsers) { _, new in core.setIncludesBrowserMedia(new) }
            } footer: {
                Text(String(
                    localized: "settings.nowPlaying.browsers.footer",
                    // swiftlint:disable:next line_length
                    defaultValue: "Includes music playing in Safari, Chrome, and other browsers. This can make the player appear for autoplay videos on websites."
                ))
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - System HUD

private struct SystemHUDSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.suppressesNativeOSDKey) private var suppress = false

    private var canSuppress: Bool {
        core.permissionMonitor.isGranted && core.osdSuppressor != nil
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $suppress) {
                    Text(String(localized: "settings.hud.suppress", defaultValue: "Replace the system indicators"))
                }
                .disabled(!canSuppress)
                .onChange(of: suppress) { _, new in core.setNativeOSDSuppression(new) }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(
                        localized: "settings.hud.suppress.footer",
                        defaultValue: "Hides the built-in volume and brightness HUDs and shows Crema's instead."
                    ))
                    if !canSuppress {
                        Text(String(
                            localized: "settings.hud.suppress.needsPermission",
                            defaultValue: "Requires Accessibility access — grant it in the Permissions tab."
                        ))
                        .foregroundStyle(.orange)
                    }
                }
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Permissions

private struct PermissionsSettingsView: View {
    let core: AppCore

    private var granted: Bool { core.permissionMonitor.isGranted }

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Label(
                        granted
                            ? String(localized: "settings.permissions.granted", defaultValue: "Granted")
                            : String(localized: "settings.permissions.notGranted", defaultValue: "Not granted"),
                        systemImage: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(granted ? .green : .orange)
                } label: {
                    Text(String(localized: "settings.permissions.accessibility", defaultValue: "Accessibility"))
                }

                if !granted {
                    Button(String(localized: "settings.permissions.grant", defaultValue: "Grant Accessibility Access…")) {
                        core.requestAccessibilityAccess()
                    }
                }
            } footer: {
                Text(String(
                    localized: "settings.permissions.footer",
                    // swiftlint:disable:next line_length
                    defaultValue: "Crema needs Accessibility access to capture the media keys — for its volume and brightness HUDs and to replace the system indicators. Without it the app still runs; it just can't react to those keys. Granting is picked up automatically, no relaunch needed."
                ))
                .settingsFootnote()
            }
        }
        .formStyle(.grouped)
    }
}

private extension View {
    /// The muted, small footnote style shared by every Settings section footer.
    func settingsFootnote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
