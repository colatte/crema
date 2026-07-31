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
    @State private var style: Style
    /// Whether any connected display RENDERS Card — the gate for the Card-scoped
    /// Indicator picker below. A mirror of what is drawn, not of the declaration:
    /// the two disagree on notchless hardware, where the default declaration is
    /// Notch and every display draws Card.
    @State private var rendersCard: Bool
    /// Whether any connected display actually draws the notch skin — the signal
    /// that separates "Notch selected and honoured" from "Notch selected and
    /// falling back everywhere", which is what the footer has to say out loud.
    @State private var rendersNotch: Bool
    @AppStorage(Preferences.hudIndicatorStyleKey) private var indicatorStyle = HUDIndicatorStyle.slider.rawValue
    /// Mirrors the real login-item status (enabled or pending approval), and is
    /// re-read from it after every attempt — the toggle is a view onto reality,
    /// never a wish that outran it.
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool

    init(core: AppCore) {
        self.core = core
        // Pinned-latent (see CONTRACTS-AUDIT S4): both mirrors are seeded once and
        // re-read only when this picker writes, so a style changed by another
        // writer — or a display hotplugged — while Settings is open leaves the
        // picker and the Indicator gate below on the stale answer until the window
        // reopens.
        _style = State(initialValue: core.currentStyle())
        _rendersCard = State(initialValue: core.rendersAnywhere(.card))
        _rendersNotch = State(initialValue: core.rendersAnywhere(.notch))
        _launchesAtLogin = State(initialValue: core.loginItem.isEnabled || core.loginItem.requiresApproval)
        _loginNeedsApproval = State(initialValue: core.loginItem.requiresApproval)
    }

    /// Notch is what the user picked, and nothing on screen is honouring it.
    /// Deliberately not `!rendersNotch` alone: with Card or Classic selected there
    /// is no fallback to report, and the generic sentence is the right one.
    private var fallbackIsInEffect: Bool {
        style == .notch && !rendersNotch && rendersCard
    }

    var body: some View {
        Form {
            // Style and Indicator sit in adjacent Sections so each footer stays
            // welded to the control it explains (one shared footer read as
            // ambiguous — which sentence scoped which picker). Adjacency still
            // carries the proximity-scope: the indicator is a facet of the Card
            // style, right below it.
            Section {
                // Pictures rather than a menu of three nouns: the names describe a
                // shape in a place, which a person has not seen yet at the moment
                // they are asked to choose. Each thumbnail is computed from that
                // skin's own frame rule, so it cannot describe a layout the app no
                // longer draws.
                LabeledContent {
                    StylePicker(selection: $style)
                } label: {
                    Text(String(localized: "settings.general.style", defaultValue: "Style"))
                }
                // The declaration decides what every display renders, so the
                // Indicator gate is re-read from the panels right after they are
                // re-resolved — never inferred from `new`, which says nothing about
                // which of the connected displays has a slit.
                .onChange(of: style) { _, new in
                    core.setStyleEverywhere(new)
                    rendersCard = core.rendersAnywhere(.card)
                    rendersNotch = core.rendersAnywhere(.notch)
                }
            } footer: {
                // Say what is happening HERE, not only what could happen. With Notch
                // selected on hardware that has none, the generic sentence left the
                // window contradicting itself: the picker reads Notch while every
                // display draws Card, and the Indicator control right below —
                // enabled, because it governs that Card HUD — looked like it
                // belonged to a style the user had not chosen. Naming the fallback
                // as a fact resolves the adjacency instead of explaining it away.
                Text(fallbackIsInEffect
                    ? String(
                        localized: "settings.general.style.footer.fallingBack",
                        defaultValue: "Applies to every display. No connected display has a notch, so every one is drawing Card."
                    )
                    : String(
                        localized: "settings.general.style.footer",
                        defaultValue: "Applies to every display. On a display without a notch, the Notch style falls back to Card."
                    ))
                    .settingsFootnote()
            }

            // Kept visible but disabled when nothing on screen renders Card (the
            // macOS dependent-setting pattern). The gate is the RENDERED style, not
            // the declared one: on hardware without a notch the default declaration
            // is Notch while every display draws Card, so gating on the declaration
            // grayed out the only control over that HUD's appearance in the state
            // the app ships in (docs/DECISIONS.md: rendered-style-gates-settings).
            // The footer still names the scope.
            Section {
                Picker(selection: $indicatorStyle) {
                    ForEach(HUDIndicatorStyle.allCases, id: \.rawValue) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                } label: {
                    Text(String(localized: "settings.hud.indicator", defaultValue: "Indicator style"))
                }
                .disabled(!rendersCard)
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

// MARK: - Permissions

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

// Internal rather than fileprivate: the tab views live in their own files now
// (SettingsView.swift was approaching the 500-line ceiling with no opt-out, and
// two more rows were going in), and every one of them dresses its footers with
// this.
extension View {
    /// The muted, small footnote style shared by every Settings section footer.
    func settingsFootnote() -> some View {
        font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
