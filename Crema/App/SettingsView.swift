import SwiftUI

/// The Preferences window: a native macOS tabbed Settings scene. Each tab is a
/// grouped Form. Every control binds to the same persisted key the behavior
/// already reads (via @AppStorage) and applies its change live through an
/// AppCore method on change — so nothing here duplicates a preference or needs
/// a relaunch.
@MainActor
struct SettingsView: View {
    enum Tab: String {
        case general, nowPlaying, systemHUD, permissions, about
    }

    let core: AppCore
    @State private var selectedTab: Tab

    init(core: AppCore) {
        self.core = core
        var initial = Tab.general
        #if DEBUG
        // Screenshot/dev harness: `-CremaSettingsInitialTab about` decides the
        // tab this window LANDS on when it opens (by ⌘, or the menu — nothing
        // opens it programmatically; the modern Settings scene has no
        // supported selector for that). DEBUG-only read; the selection state
        // itself is ordinary TabView plumbing.
        if let raw = UserDefaults.standard.string(forKey: "CremaSettingsInitialTab"),
           let tab = Tab(rawValue: raw) {
            initial = tab
        }
        #endif
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.general", defaultValue: "General"), systemImage: "gearshape") }
                .tag(Tab.general)
            NowPlayingSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.nowPlaying", defaultValue: "Now Playing"), systemImage: "music.note") }
                .tag(Tab.nowPlaying)
            SystemHUDSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.systemHUD", defaultValue: "System HUD"), systemImage: "slider.horizontal.3") }
                .tag(Tab.systemHUD)
            PermissionsSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.permissions", defaultValue: "Permissions"), systemImage: "lock.shield") }
                .tag(Tab.permissions)
            AboutSettingsView()
                .tabItem { Label(String(localized: "settings.tab.about", defaultValue: "About"), systemImage: "info.circle") }
                .tag(Tab.about)
        }
        .frame(width: 500)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    let core: AppCore
    @State private var style: Style
    @AppStorage(Preferences.hudIndicatorStyleKey) private var indicatorStyle = HUDIndicatorStyle.slider.rawValue
    /// Mirrors the real login-item status (enabled or pending approval), and is
    /// re-read from it after every attempt — the toggle is a view onto reality,
    /// never a wish that outran it.
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool

    init(core: AppCore) {
        self.core = core
        // Pinned-latent (see CONTRACTS-AUDIT S4): `style` is seeded once and
        // never re-synced, so a style changed by another writer while Settings
        // is open leaves this picker — and the Indicator's .disabled(style != .card)
        // gate below — showing the stale value until the window reopens.
        _style = State(initialValue: core.currentStyle())
        _launchesAtLogin = State(initialValue: core.loginItem.isEnabled || core.loginItem.requiresApproval)
        _loginNeedsApproval = State(initialValue: core.loginItem.requiresApproval)
    }

    var body: some View {
        Form {
            // Style and Indicator sit in adjacent Sections so each footer stays
            // welded to the control it explains (one shared footer read as
            // ambiguous — which sentence scoped which picker). Adjacency still
            // carries the proximity-scope: the indicator is a facet of the Card
            // style, right below it.
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

            // Kept visible but disabled outside Card (the macOS dependent-setting
            // pattern) — the declared global style is the source of truth, so a
            // notchless display whose Notch selection renders as Card still reads
            // the picker as inert; the footer names the scope.
            Section {
                Picker(selection: $indicatorStyle) {
                    ForEach(HUDIndicatorStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                } label: {
                    Text(String(localized: "settings.hud.indicator", defaultValue: "Indicator style"))
                }
                .disabled(style != .card)
                .onChange(of: indicatorStyle) { _, new in
                    core.setHUDIndicatorStyle(HUDIndicatorStyle(rawValue: new) ?? .slider)
                }
            } footer: {
                Text(String(
                    localized: "settings.hud.indicator.footer",
                    defaultValue: "Applies to the Card style."
                ))
                .settingsFootnote()
            }

            Section {
                // A custom binding (not onChange): the setter routes the intent
                // through AppCore and reflects the real status it returns, so a
                // failed registration snaps it back and a "requires approval"
                // result keeps it on with the note below — and mutating state
                // in the setter can't re-fire itself.
                Toggle(isOn: Binding(
                    get: { launchesAtLogin },
                    set: { wanted in
                        (launchesAtLogin, loginNeedsApproval) = core.setLaunchesAtLogin(wanted)
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
                    // The indicator-style picker lives in General, beside the
                    // Style picker it depends on — this line is the trail for
                    // whoever comes to the HUD tab looking for it.
                    Text(String(
                        localized: "settings.hud.appearanceHint",
                        defaultValue: "The indicator's appearance is set in the General tab."
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

// MARK: - About

/// A plaque, not a form: the identity, the live version, the signature line
/// and quiet links — no controls, so it skips the grouped Form the other tabs
/// use. Everything display-side comes from the bundle (icon and versions are
/// never hardcoded), so a release build shows its stamped numbers.
private struct AboutSettingsView: View {
    private static let githubURL = URL(string: "https://github.com/vctorgriggi/Crema")
    private static let issuesURL = URL(string: "https://github.com/vctorgriggi/Crema/issues")
    private static let kofiURL = URL(string: "https://ko-fi.com/colatteio")

    var body: some View {
        VStack(spacing: 6) {
            // null_resettable in AppKit (imported as an IUO — reads never
            // return nil); the fallback keeps the no-force-unwrap discipline
            // explicit. Decorative: the app name right below is the label.
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .frame(width: 110, height: 110)
                .padding(.bottom, 2)
                .accessibilityHidden(true)
            Text(verbatim: appName)
                .font(.title2.weight(.semibold))
            Text(String(localized: "about.version", defaultValue: "Version \(shortVersion) (\(buildNumber))"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(String(localized: "about.signature", defaultValue: "made with ☕ by Colatte"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            HStack(spacing: 18) {
                link(String(localized: "about.link.github", defaultValue: "GitHub"), Self.githubURL)
                link(String(localized: "about.link.reportIssue", defaultValue: "Report an issue"), Self.issuesURL)
                link(String(localized: "about.link.kofi", defaultValue: "Support on Ko-fi"), Self.kofiURL)
            }
            .font(.callout)
            .padding(.top, 10)
            // Attribution, not capability: true in every configuration (the
            // updater does not compile in Debug), and it covers the vendored
            // mediaremote-adapter — BSD-3-Clause, the one dependency whose
            // license asks for the notice in the distributed materials.
            Text(String(localized: "about.credits", defaultValue: "Built with Sparkle and mediaremote-adapter."))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    /// Product name from the bundle (display name, then name), so a rename
    /// never leaves a stale plaque; the literal is only the last-resort
    /// fallback and is brand, not translatable chrome.
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Crema"
    }

    private var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    @ViewBuilder
    private func link(_ title: String, _ url: URL?) -> some View {
        // The URL initializers are statically valid; the optional guard is the
        // no-force-unwrap discipline, not a reachable branch.
        if let url {
            Link(title, destination: url)
        }
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
