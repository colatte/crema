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
        // tab this window LANDS on when it opens. The app's own opens go through
        // `openSettings` (SwiftUI's OpenSettingsAction, macOS 14), from the menu,
        // and the ones that name a tab steer it with `settingsNavigation`, which
        // wins over this flag. An unknown name parses to nil and lands on
        // General silently, which is the harness's contract: it steers a screenshot
        // run, so a stale flag is worth a wrong tab and never a crash.
        // DEBUG-only read; the selection state itself is ordinary TabView plumbing.
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

/// Style at both of its scopes, the Card's indicator after the displays, then
/// opening at login.
///
/// Style leads because it is what a person came here to change, and both of its
/// scopes are in one pane on purpose: the all-displays declaration SWEEPS the
/// per-display styles, and a tab away that sweep would be a warning about sections
/// the reader cannot see. So the declaration sits above the very list it replaces.
///
/// The per-display list is reactive; the rendered-style mirrors are seeded once and
/// re-read after every write this pane makes and every display change — a
/// pinned-latent tradeoff (docs/CONTRACTS.md: S4) whose residual is a style picked
/// from the menu bar while this window is open.
/// A list whose rows ARE the displays cannot take that deal: a row outliving its
/// monitor is a control over a screen the user cannot see, and a display plugged in
/// with the window open would have no row at all until Settings is closed and
/// reopened. The roster it reads is the SAME reading that builds the panels, so the
/// pane cannot list a display no panel carries.
private struct GeneralSettingsView: View {
    let core: AppCore
    /// The all-displays declaration, as the picker holds it.
    @State private var style: Style
    /// The displays RENDERING Card — whether the indicator row exists at all, and
    /// the displays its sentence names. A mirror of what is drawn, not of the
    /// declaration: the two disagree on notchless hardware, where the default
    /// declaration is Notch and every display draws Card.
    @State private var cardDisplays: Set<DisplayUUID>
    /// Whether any connected display actually draws the notch skin — the signal
    /// that separates "Notch declared and honoured" from "Notch declared and
    /// falling back everywhere", which is what the footer has to say out loud.
    @State private var rendersNotch: Bool
    /// The desk both tile rows stand on, read once when this pane is built. Asked
    /// of the core rather than of each row, so the two rows in one Section cannot
    /// end up on different desks.
    @State private var wallpaper: NSImage?
    /// Mirrors the real login-item status (enabled or pending approval), and is
    /// re-read from it after every attempt — the toggle is a view onto reality,
    /// never a wish that outran it.
    @State private var launchesAtLogin: Bool
    @State private var loginNeedsApproval: Bool

    init(core: AppCore) {
        self.core = core
        // One seed rule for both windows that carry this section — the reads and
        // their why live in StyleSectionSeed, never respelled here.
        let seed = StyleSectionSeed(core: core)
        _style = State(initialValue: seed.style)
        _cardDisplays = State(initialValue: seed.cardDisplays)
        _rendersNotch = State(initialValue: seed.rendersNotch)
        _wallpaper = State(initialValue: seed.wallpaper)
        _launchesAtLogin = State(initialValue: seed.launchesAtLogin)
        _loginNeedsApproval = State(initialValue: seed.loginNeedsApproval)
    }

    private var rendersCard: Bool {
        !cardDisplays.isEmpty
    }

    /// The displays drawing Card, in the list's own order and under the list's own
    /// names, so the sentence and the rows above it call each screen the same thing.
    private var cardDisplayNames: [String] {
        core.displayRoster.displays
            .filter { cardDisplays.contains($0.id) }
            .map { DisplayStyleRow.title(for: $0) }
    }

    /// What the panels draw, re-read right after they are re-resolved — never
    /// inferred from what was written, which says nothing about which displays have
    /// a slit.
    private func rereadRenderedStyles() {
        cardDisplays = core.displaysRendering(.card)
        rendersNotch = core.rendersAnywhere(.notch)
    }

    private var fallbackIsInEffect: Bool {
        Style.fallsBackToCard(declared: style, rendersNotch: rendersNotch, rendersCard: rendersCard)
    }

    /// Whether any connected display carries a style of its own. Read where it is
    /// used instead of mirrored into state: it is one key read per display, and a
    /// seeded copy would go on promising a replacement after the declaration
    /// already swept them — the pinned-latent cost the mirrors above accept and
    /// this sentence cannot.
    private var hasPerDisplayStyles: Bool {
        PerDisplayStyleOverride.exists(among: core.displayRoster.displays)
    }

    /// Whether there is a per-display answer the section above cannot give. Asked of
    /// `DisplayStyleOptions` rather than answered here, because the reason is not a
    /// count of screens: the row is where the now-playing switch lives, and there is
    /// nowhere else in the app to turn that surface on or off.
    private var offersPerDisplayList: Bool {
        DisplayStyleOptions.listIsOffered(for: core.displayRoster.displays)
    }

    var body: some View {
        Form {
            Section {
                // Pictures rather than a menu of three nouns: the names describe a
                // shape in a place, which a person has not seen yet at the moment
                // they are asked to choose. Each thumbnail is computed from that
                // skin's own frame rule, so it cannot describe a layout the app no
                // longer draws. No geometry: this one speaks for every display, so
                // no screen's slit decides which tiles are offerable.
                LabeledContent {
                    StylePicker(selection: $style, wallpaper: wallpaper)
                } label: {
                    Text(String(localized: "settings.general.style", defaultValue: "Style"))
                }
                // The declaration decides what every display renders, so the
                // rendered-style mirrors are re-read from the panels right after
                // they are re-resolved — never inferred from `new`, which says
                // nothing about which of the connected displays has a slit.
                .onChange(of: style) { _, new in
                    core.setStyleEverywhere(new)
                    rereadRenderedStyles()
                }
            } header: {
                Text(String(localized: "settings.displays.allDisplays", defaultValue: "All displays"))
            } footer: {
                // Say what is happening HERE, not only what could happen. With Notch
                // declared on hardware that has none, the generic sentence alone
                // has the window contradict itself: the picker reads Notch while
                // every display draws Card. Naming the fallback as a fact resolves
                // that instead of explaining it away.
                VStack(alignment: .leading, spacing: 4) {
                    Text(fallbackIsInEffect
                        ? String(
                            localized: "settings.general.style.footer.fallingBack",
                            defaultValue: "Applies to every display. No connected display has a notch, so every one is drawing Card."
                        )
                        : String(
                            localized: "settings.general.style.footer",
                            defaultValue: "Applies to every display. On a display without a notch, the Notch style falls back to Card."
                        ))
                    // "Applies to every display" is only half of what picking here
                    // does: it also drops the per-display styles. Said only when
                    // there is something to replace — a warning about nothing
                    // teaches the reader to skip the footer.
                    //
                    // The sentence points DOWN, and may: an override existing among
                    // the connected displays is one of the clauses that opens the
                    // list, so whenever this line is drawn the section it names is
                    // drawn under it. The welcome tour makes the same declaration
                    // with no list beneath it, and owes its own wording for that.
                    if hasPerDisplayStyles {
                        Text(String(
                            localized: "settings.general.style.footer.replacesPerDisplay",
                            defaultValue: "This also replaces the per-display styles below."
                        ))
                    }
                }
                .settingsFootnote()
            }

            // Offered wherever there is a display at all. The style popup on a lone
            // panel does repeat the declaration above — but the row also carries the
            // only "show the player here" switch the app has, and withholding it
            // leaves a single-laptop install with the surface on and no way to turn
            // it off, the mirror of a lone external display in the same spot.
            if offersPerDisplayList {
                Section {
                    ForEach(core.displayRoster.displays, id: \.id) { screen in
                        DisplayStyleRow(screen: screen, core: core, wallpaper: wallpaper) {
                            rereadRenderedStyles()
                        }
                    }
                } header: {
                    Text(String(localized: "settings.general.displays", defaultValue: "Displays"))
                } footer: {
                    // One sentence for the list rather than one per row: the toggle
                    // above it repeats per display, and an explanation per row would
                    // make a two-monitor pane read as the same paragraph printed
                    // twice.
                    Text(String(
                        localized: "settings.displays.showNowPlaying.footer",
                        defaultValue: "The player appears on each display switched on here. On by default for the built-in display."
                    ))
                    .settingsFootnote()
                }
            }

            // Offered where some display draws Card, and ABSENT rather than greyed
            // out where none does (docs/DECISIONS.md: rendered-style-gates-settings).
            // The gate is `cardDisplays`, the rendered-style mirror read from
            // `core.displaysRendering(.card)` and re-read after every style write in
            // this pane, so a pick above makes this section appear or go at once.
            if rendersCard {
                CardIndicatorSection(core: core, wallpaper: wallpaper, displayNames: cardDisplayNames)
            }

            Section {
                LaunchAtLoginToggle(core: core, isOn: $launchesAtLogin, needsApproval: $loginNeedsApproval)
            } footer: {
                if loginNeedsApproval {
                    // The sentence names no PATH, and that is the fix rather
                    // than a shorter sentence: macOS 15 renamed the pane to
                    // "Login Items & Extensions" (Apple: "Change Login Items &
                    // Extensions settings on Mac") and the app supports 14+, so
                    // any written path is wrong on one of them — and a button
                    // that opens the pane cannot be wrong on either.
                    Text(String(
                        localized: "settings.general.launchAtLogin.needsApproval",
                        defaultValue: "Approve Crema in System Settings to finish enabling this."
                    ))
                    .foregroundStyle(.orange)
                    .settingsFootnote()
                    Button(String(
                        localized: "settings.general.launchAtLogin.openSettings",
                        defaultValue: "Open Login Items Settings…"
                    )) {
                        core.openLoginItemsSettings()
                    }
                    .buttonStyle(.link)
                    .settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
        // The indicator section appears and goes with what the displays draw, and
        // an instant insertion jumps every control under it in the same frame as
        // the click that caused it. Scoped to that one fact.
        .animation(.default, value: rendersCard)
        // A display plugged in or out changes what is drawn; the panels have already
        // been rebuilt by the time the roster this reads from moves
        // (`AppCore.applyScreenRoster`).
        .onChange(of: core.displayRoster.displays) { rereadRenderedStyles() }
    }
}

// MARK: - Now Playing

private struct NowPlayingSettingsView: View {
    let core: AppCore
    @AppStorage(Preferences.reactiveNowPlayingKey) private var reactive = Preferences.defaultReactiveNowPlaying
    @AppStorage(Preferences.showsPlaybackControlsKey) private var showsControls = Preferences.defaultShowsPlaybackControls
    @AppStorage(Preferences.includesBrowserMediaKey) private var includesBrowsers = Preferences.defaultIncludesBrowserMedia

    var body: some View {
        Form {
            // The degradation this tab states: with nothing reporting, every switch
            // below configures a surface that never appears, and without it here the
            // menu would be the only place saying so. Same shape the Indicators tab
            // gives the neighbour integration, and the footer names the channel rather
            // than a fault — the resting case is nobody playing anything.
            //
            // `isActive` is safe to read from a Form body, unlike the readings behind
            // the menu: it is a guarded mirror written only on a chain selection edge
            // (NowPlayingMonitor), so it invalidates this pane when the answer
            // changes and never on a track tick.
            Section {
                LabeledContent {
                    Text(core.nowPlayingMonitor.isActive
                        ? String(localized: "settings.nowPlaying.source.reporting", defaultValue: "Reporting")
                        : String(localized: "settings.nowPlaying.source.notReporting", defaultValue: "Not reporting"))
                        .foregroundStyle(core.nowPlayingMonitor.isActive ? .primary : .secondary)
                } label: {
                    Text(String(localized: "settings.nowPlaying.source", defaultValue: "Media source"))
                }
            } footer: {
                Text(String(
                    localized: "settings.nowPlaying.source.footer",
                    // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
                    defaultValue: "Crema reads what’s playing from the system. With nothing reporting, the player stays hidden and the options below have nothing to act on."
                ))
                .settingsFootnote()
            }

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
                    // swiftlint:disable:next line_length - one line, so check-catalog.py reads the defaultValue
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
            // Coffee as a word, never a glyph, and the brand as prose: the
            // lettering "colatte." is the logo, and a logo is never typed in a
            // text font (the Colatte brand manual, golden rule 2). Plain text
            // also reads the same under VoiceOver, so no separate label.
            Text(String(localized: "about.signature", defaultValue: "made with coffee by Colatte"))
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

// Internal rather than fileprivate: the panes and rows that dress their footers
// with this are spread over several files, and a fileprivate helper would be
// copied into each of them instead.
extension View {
    /// The muted, small footnote style shared by every Settings section footer.
    ///
    /// `.subheadline`: one point under the 13 pt control labels is no separation
    /// for text three to four times longer, and a pane without it reads as
    /// paragraphs with a control in them rather than controls with notes.
    func settingsFootnote() -> some View {
        font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
