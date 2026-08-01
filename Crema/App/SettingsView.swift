import SwiftUI

/// The Preferences window: a native macOS tabbed Settings scene. Each tab is a
/// grouped Form. Every control binds to the same persisted key the behavior
/// already reads (via @AppStorage) and applies its change live through an
/// AppCore method on change — so nothing here duplicates a preference or needs
/// a relaunch.
@MainActor
struct SettingsView: View {
    let core: AppCore
    @State private var selectedTab: SettingsTab

    init(core: AppCore) {
        self.core = core
        var initial = SettingsTab.general
        #if DEBUG
        // Screenshot/dev harness: `-CremaSettingsInitialTab about` decides the
        // tab this window LANDS on when it opens (by ⌘, or the menu — nothing
        // opens it programmatically; the modern Settings scene has no
        // supported selector for that). DEBUG-only read; the selection state
        // itself is ordinary TabView plumbing.
        if let raw = UserDefaults.standard.string(forKey: "CremaSettingsInitialTab"),
           let tab = SettingsTab(rawValue: raw) {
            initial = tab
        }
        #endif
        _selectedTab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.general", defaultValue: "General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            // Where style lives, at both of its scopes: what every display draws,
            // then what one of them draws instead. Split across two tabs it read as
            // two separate settings, and the all-displays pick — which sweeps every
            // per-display override — was made in the tab that showed none of them.
            DisplaysSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.displays", defaultValue: "Displays"), systemImage: "display") }
                .tag(SettingsTab.displays)
            NowPlayingSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.nowPlaying", defaultValue: "Now Playing"), systemImage: "music.note") }
                .tag(SettingsTab.nowPlaying)
            SystemHUDSettingsView(core: core)
                .tabItem {
                    Label(
                        String(localized: "settings.tab.indicators", defaultValue: "Indicators"),
                        systemImage: "slider.horizontal.3"
                    )
                }
                .tag(SettingsTab.indicators)
            PermissionsSettingsView(core: core)
                .tabItem { Label(String(localized: "settings.tab.permissions", defaultValue: "Permissions"), systemImage: "lock.shield") }
                .tag(SettingsTab.permissions)
            AboutSettingsView()
                .tabItem { Label(String(localized: "settings.tab.about", defaultValue: "About"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: 500)
        // A warning that offers its own fix lands ON the fix, rather than naming
        // the tab and leaving the walk to the reader. Consumed immediately, so it
        // steers the window once and never drags it back afterwards.
        .onChange(of: core.settingsNavigation.requestedTab) { _, requested in
            guard let requested else { return }
            selectedTab = requested
            core.settingsNavigation.consume()
        }
        .onAppear {
            if let requested = core.settingsNavigation.requestedTab {
                selectedTab = requested
                core.settingsNavigation.consume()
            }
        }
    }
}

// MARK: - General

private struct GeneralSettingsView: View {
    let core: AppCore
    /// Mirrors the real login-item status (enabled or pending approval), and is
    /// re-read from it after every attempt — the toggle is a view onto reality,
    /// never a wish that outran it.
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool

    init(core: AppCore) {
        self.core = core
        _launchesAtLogin = State(initialValue: core.loginItem.isEnabled || core.loginItem.requiresApproval)
        _loginNeedsApproval = State(initialValue: core.loginItem.requiresApproval)
    }

    var body: some View {
        Form {
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
                    Text(String(localized: "settings.nowPlaying.reactive", defaultValue: "Show the player automatically"))
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

// MARK: - About

/// A plaque, not a form: the identity, the live version, the signature line
/// and quiet links — no controls, so it skips the grouped Form the other tabs
/// use. Everything display-side comes from the bundle (icon and versions are
/// never hardcoded), so a release build shows its stamped numbers.
private struct AboutSettingsView: View {
    private static let githubURL = URL(string: "https://github.com/colatte/crema")
    private static let issuesURL = URL(string: "https://github.com/colatte/crema/issues")
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
                // The one string in the window someone else asks for. Selectable so
                // it can be pasted into a report instead of transcribed.
                .textSelection(.enabled)
            Text(String(localized: "about.signature", defaultValue: "made with ☕ by Colatte"))
                .font(.callout)
                .foregroundStyle(.secondary)
                // The app's one deliberate glyph is branding, not state — but
                // VoiceOver reads it as "hot beverage" mid-sentence, so it is spoken
                // as the word it stands for.
                .accessibilityLabel(String(
                    localized: "about.signature.accessibility",
                    defaultValue: "made with coffee by Colatte"
                ))
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

// Internal rather than fileprivate: the tab views live in their own files now
// (SettingsView.swift was approaching the 500-line ceiling with no opt-out, and
// two more rows were going in), and every one of them dresses its footers with
// this.
extension View {
    /// The muted, small footnote style shared by every Settings section footer.
    ///
    /// A step below `.callout`, which sat one point under the 13 pt control labels —
    /// one point of separation for text three to four times longer, so every pane
    /// read as paragraphs with a control in them rather than controls with notes.
    func settingsFootnote() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
