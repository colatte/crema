import SwiftUI

/// One section per connected display: the style that screen draws, and whether
/// the now-playing surface appears on it.
///
/// The list is reactive, and deliberately unlike its neighbour in General, which
/// seeds its mirrors once and re-reads only when its own picker writes — a
/// pinned-latent tradeoff (docs/internal/archive/CONTRACTS-AUDIT.md: S4) that
/// costs a stale value there. A list whose rows ARE the displays cannot take that
/// deal: a row outliving its monitor is a control over a screen the user cannot
/// see, and a display plugged in with the window open would have no row at all
/// until Settings is closed and reopened. The roster it reads is the SAME reading
/// that builds the panels, so the tab cannot list a display no panel carries.
struct DisplaysSettingsView: View {
    let core: AppCore

    var body: some View {
        Form {
            ForEach(core.displayRoster.displays, id: \.id) { screen in
                DisplaySettingsRow(screen: screen, core: core)
            }
        }
        .formStyle(.grouped)
    }
}

/// One display's own settings.
///
/// A View of its own rather than a block built inside the list: SwiftUI tracks
/// observation and storage per BODY, so folded into the parent every row's keys
/// would be read once while the list was being built — the pinned-latent shape
/// again, in the one place that cannot afford it — and a write to any display's
/// key would rebuild all of them.
private struct DisplaySettingsRow: View {
    let screen: ScreenDescription
    let core: AppCore
    /// This display's override and its "show now playing here" flag, bound raw:
    /// @AppStorage is the only side of a preference a control can reach, and
    /// these keys are per-display, so the spelling comes from Preferences rather
    /// than a literal — the same key from the other side.
    @AppStorage private var styleRaw: String?
    @AppStorage private var showsNowPlaying: Bool
    /// The all-displays declaration, watched because it is the fallback of what
    /// this row shows: a declaration made in General sweeps every override, and a
    /// row that missed it would keep naming a style this display no longer draws.
    @AppStorage(Preferences.declaredStyleKey) private var declaredStyleRaw: String?

    init(screen: ScreenDescription, core: AppCore) {
        self.screen = screen
        self.core = core
        _styleRaw = AppStorage(Preferences.styleKey(for: screen.id))
        _showsNowPlaying = AppStorage(
            wrappedValue: Preferences.defaultShowsNowPlaying(isInternal: screen.isInternal),
            Preferences.showsNowPlayingKey(for: screen.id)
        )
    }

    var body: some View {
        Section {
            LabeledContent {
                // The pictures are of THIS screen, so a style it cannot draw is
                // offered dimmed instead of silently swapped out.
                StylePicker(selection: pickedStyle, on: screen.geometry)
            } label: {
                // The same key the picker announces to VoiceOver: a different
                // word here would make the control say one thing and show another.
                Text(String(localized: "settings.general.style", defaultValue: "Style"))
            }
            .onChange(of: styleRaw) { _, new in
                // Nil is this display returning to the declaration — the button
                // below, or a declaration in General sweeping every override —
                // and both of those already applied their own live effect.
                guard let style = PerDisplayStyleOverride.value(fromRawValue: new) else { return }
                core.setStyle(style, for: screen.id)
            }

            if ownsItsStyle {
                // One core call rather than a write plus an onChange: inheriting
                // IS the absence of the key, and `clearStyle` removes it and
                // re-resolves the panels in the same step.
                Button(String(
                    localized: "settings.displays.style.reset",
                    defaultValue: "Use the all-displays style"
                )) {
                    core.clearStyle(for: screen.id)
                }
            }

            Toggle(isOn: $showsNowPlaying) {
                Text(String(
                    localized: "settings.displays.showNowPlaying",
                    defaultValue: "Show now playing here"
                ))
            }
            .onChange(of: showsNowPlaying) { _, new in core.setShowsNowPlaying(new, on: screen.id) }
        } header: {
            Text(verbatim: title)
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(styleFootnote)
                if drawsTheFallback {
                    Text(String(
                        localized: "settings.displays.style.footer.noNotch",
                        defaultValue: "This display has no notch, so Notch draws as Card here."
                    ))
                }
                Text(String(
                    localized: "settings.displays.showNowPlaying.footer",
                    defaultValue: "The player appears on this display. On by default for the built-in display."
                ))
            }
            .settingsFootnote()
        }
    }

    /// The row's title. The built-in panel is named in the app's own vocabulary —
    /// the word the Indicators tab and this section's own footer already use for
    /// it, and one that reads the same in both languages where AppKit's name for
    /// it does not. Every other display carries the name macOS shows, the only
    /// name a person can match against the thing on their desk; the border hands
    /// that name over verbatim and never invents one, so an empty string falls to
    /// the generic noun rather than to an untitled row.
    private var title: String {
        if screen.isInternal {
            return String(localized: "settings.displays.builtIn", defaultValue: "Built-in display")
        }
        return screen.name.isEmpty
            ? String(localized: "settings.displays.unnamed", defaultValue: "Display")
            : screen.name
    }

    /// What the picker reads and what a pick writes. The key is the source of
    /// truth — the write persists it, and the live effect is the core call in the
    /// onChange above, which is what every Settings control owes.
    private var pickedStyle: Binding<Style> {
        Binding(get: { chosenStyle }, set: { styleRaw = $0.rawValue })
    }

    /// What the picker shows: this display's own style when it has one, else the
    /// all-displays declaration. Resolved by Preferences — the rule the panels
    /// render by — because a second copy here is how a row comes to name a style
    /// the screen does not draw (docs/DECISIONS.md: global-style-default).
    private var chosenStyle: Style {
        Preferences.style(overrideRawValue: styleRaw, declaredRawValue: declaredStyleRaw)
    }

    private var ownsItsStyle: Bool {
        PerDisplayStyleOverride.value(fromRawValue: styleRaw) != nil
    }

    /// This display draws something other than what the picker reads — today the
    /// notch skin on a panel with no slit. Stated as a fact in effect, never as a
    /// hypothetical: the General footer learned that a sentence about a fallback
    /// that is not happening reads as a warning about the style just picked.
    private var drawsTheFallback: Bool {
        !chosenStyle.isHonoured(on: screen.geometry)
    }

    /// Which way this display is pointed, and what the person can do about it —
    /// the pair the reset button above appears and disappears with.
    private var styleFootnote: String {
        ownsItsStyle
            ? String(
                localized: "settings.displays.style.footer.own",
                defaultValue: "This display has its own style. Choosing in General replaces it."
            )
            : String(
                localized: "settings.displays.style.footer.inherits",
                defaultValue: "This display follows the all-displays style. Pick one here to give it its own."
            )
    }
}

/// The per-display style override as a VIEW reads it: from the raw value, which
/// is the only side of the preference an @AppStorage binding can reach
/// (`Preferences.styleKey(for:)` is exposed for exactly that). Same rule as
/// `Preferences.styleOverride(for:)` on the store side — a rawValue a future
/// version retired reads as INHERITS, because it is not a choice the user made
/// and presenting it as one would name a style the app can no longer draw
/// (docs/DECISIONS.md: global-style-default).
enum PerDisplayStyleOverride {
    /// Delegates to the one home of the retired-rawValue rule: a view only
    /// reaches the raw key (@AppStorage), so the store's static is the seam.
    static func value(fromRawValue raw: String?) -> Style? {
        Preferences.styleOverride(fromRawValue: raw)
    }

    /// Whether any of these displays carries a style of its own — the fact the
    /// all-displays footer has to state, since declaring there replaces them all.
    /// One synchronous key read per connected display, on the store @AppStorage
    /// writes: it costs what a row already costs and adds no observation. The
    /// price is a read only as fresh as the body that asks — acceptable because
    /// the sentence is a warning beside the declaration, and the sweep it warns
    /// about happens either way.
    static func exists(among displays: [ScreenDescription], in defaults: UserDefaults = .standard) -> Bool {
        displays.contains { value(fromRawValue: defaults.string(forKey: Preferences.styleKey(for: $0.id))) != nil }
    }
}
