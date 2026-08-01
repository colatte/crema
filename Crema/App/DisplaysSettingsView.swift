import SwiftUI

/// Style, at both of its scopes, in one tab: the declaration that speaks for
/// every display, then a section per connected display — the style that screen
/// draws, and whether the now-playing surface appears on it.
///
/// The declaration used to live in General, one tab away from the overrides it
/// sweeps, which made the same choice read as two settings. It leads here instead,
/// because that is the order the two answer in: what every display draws, then what
/// one of them draws instead.
///
/// The per-display list is reactive; the declaration's mirrors below are seeded
/// once and re-read only when that picker writes — a pinned-latent tradeoff
/// (docs/internal/archive/CONTRACTS-AUDIT.md: S4) that costs a stale value there.
/// A list whose rows ARE the displays cannot take that deal: a row outliving its
/// monitor is a control over a screen the user cannot see, and a display plugged in
/// with the window open would have no row at all until Settings is closed and
/// reopened. The roster it reads is the SAME reading that builds the panels, so the
/// tab cannot list a display no panel carries.
struct DisplaysSettingsView: View {
    let core: AppCore
    /// The all-displays declaration, as the picker holds it.
    @State private var style: Style
    /// Whether any connected display RENDERS Card. A mirror of what is drawn, not
    /// of the declaration: the two disagree on notchless hardware, where the
    /// default declaration is Notch and every display draws Card.
    @State private var rendersCard: Bool
    /// Whether any connected display actually draws the notch skin — the signal
    /// that separates "Notch declared and honoured" from "Notch declared and
    /// falling back everywhere", which is what the footer has to say out loud.
    @State private var rendersNotch: Bool

    init(core: AppCore) {
        self.core = core
        _style = State(initialValue: core.currentStyle())
        _rendersCard = State(initialValue: core.rendersAnywhere(.card))
        _rendersNotch = State(initialValue: core.rendersAnywhere(.notch))
    }

    /// Notch is what the user declared, and nothing on screen is honouring it.
    /// Deliberately not `!rendersNotch` alone: with Card or Classic declared there
    /// is no fallback to report, and the generic sentence is the right one.
    private var fallbackIsInEffect: Bool {
        style == .notch && !rendersNotch && rendersCard
    }

    /// Whether any connected display carries a style of its own. Read where it is
    /// used instead of mirrored into state: it is one key read per display, and a
    /// seeded copy would go on promising a replacement after the declaration
    /// already swept them — the pinned-latent cost the mirrors above accept and
    /// this sentence cannot.
    private var hasPerDisplayStyles: Bool {
        PerDisplayStyleOverride.exists(among: core.displayRoster.displays)
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
                    StylePicker(selection: $style)
                } label: {
                    Text(String(localized: "settings.general.style", defaultValue: "Style"))
                }
                // The declaration decides what every display renders, so the
                // rendered-style mirrors are re-read from the panels right after
                // they are re-resolved — never inferred from `new`, which says
                // nothing about which of the connected displays has a slit.
                .onChange(of: style) { _, new in
                    core.setStyleEverywhere(new)
                    rendersCard = core.rendersAnywhere(.card)
                    rendersNotch = core.rendersAnywhere(.notch)
                }
            } header: {
                Text(String(localized: "settings.displays.allDisplays", defaultValue: "All displays"))
            } footer: {
                // Say what is happening HERE, not only what could happen. With Notch
                // declared on hardware that has none, the generic sentence left the
                // window contradicting itself: the picker reads Notch while every
                // display draws Card. Naming the fallback as a fact resolves that
                // instead of explaining it away.
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
                    // teaches the reader to skip the footer. The sections it names
                    // are the ones below, and the same sentence is what the welcome
                    // tour owes for making the same declaration.
                    if hasPerDisplayStyles {
                        Text(String(
                            localized: "settings.general.style.footer.replacesPerDisplay",
                            defaultValue: "This also replaces the per-display styles in the Displays tab."
                        ))
                    }
                }
                .settingsFootnote()
            }

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
    /// this row shows: a declaration made in the section above sweeps every
    /// override, and a row that missed it would keep naming a style this display no
    /// longer draws.
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
                // below, or an all-displays declaration sweeping every override —
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
                defaultValue: "This display has its own style. Choosing the all-displays style replaces it."
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
