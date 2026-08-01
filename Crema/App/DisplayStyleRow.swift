import SwiftUI

/// One display's own settings: the style it draws instead of the declaration, and
/// whether the now-playing surface appears on it.
///
/// A View of its own rather than a block built inside the list: SwiftUI tracks
/// observation and storage per BODY, so folded into the parent every row's keys
/// would be read once while the whole list was being built — the pinned-latent
/// shape, in the one place that cannot afford it — and a write to any display's key
/// would rebuild all of them.
struct DisplayStyleRow: View {
    let screen: ScreenDescription
    let core: AppCore
    /// This display's override and its "show now playing here" flag, bound raw:
    /// @AppStorage is the only side of a preference a control can reach, and these
    /// keys are per-display, so the spelling comes from Preferences rather than a
    /// literal — the same key from the other side.
    @AppStorage private var styleRaw: String?
    @AppStorage private var showsNowPlaying: Bool
    /// The all-displays declaration, watched because it is the fallback of what this
    /// row shows: a declaration made in the section above sweeps every override, and
    /// a row that missed it would keep naming a style this display no longer draws.
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
        LabeledContent {
            stylePopup
        } label: {
            Text(verbatim: title)
        }

        ForEach(footnotes, id: \.self) { footnote in
            Text(footnote).settingsFootnote()
        }

        Toggle(isOn: $showsNowPlaying) {
            Text(String(
                localized: "settings.displays.showNowPlaying",
                defaultValue: "Show now playing here"
            ))
        }
        .onChange(of: showsNowPlaying) { _, new in core.setShowsNowPlaying(new, on: screen.id) }
    }

    /// What this row offers, what it reads back and what a pick may write — decided
    /// from the two raw values and this screen's geometry, outside the chrome, so
    /// nothing below re-derives which styles this panel actually draws.
    private var options: DisplayStyleOptions {
        DisplayStyleOptions(
            overrideRawValue: styleRaw,
            declaredRawValue: declaredStyleRaw,
            geometry: screen.geometry
        )
    }

    /// A custom `Menu` of one item per option, and deliberately not a `Picker`.
    /// Measured on macOS 26.5.2 (`scripts/probes/picker-option-disabled.swift`): a
    /// `.menu` Picker DISCARDS `.disabled` on its options — the marked item read
    /// back `isEnabled == true` against an `NSPopUpButton` control reading `false` —
    /// so a style this screen cannot draw would stay clickable there whatever the
    /// chrome asked for. Here `.disabled` is honoured, but that is only what keeps
    /// such a pick out of REACH; what keeps it out of the store is
    /// `DisplayStyleOptions.write(for:)`, which answers `refused` and writes nothing.
    private var stylePopup: some View {
        Menu {
            ForEach(options.items, id: \.choice) { item in
                // A checkmark on a disabled row is not a contradiction: it is the
                // honest report of "you chose this and this screen does not draw
                // it", which is why the mark is read from the user's own key and
                // never filtered by what this panel honours
                // (docs/DECISIONS.md: selected-and-disabled-is-a-state).
                Toggle(isOn: pickBinding(for: item.choice)) {
                    Text(label(for: item.choice))
                }
                .disabled(!item.isEnabled)
            }
        } label: {
            // The closed control wears the selected item's own words, so it and the
            // open list cannot come to describe the same state differently.
            Text(label(for: options.selection))
        }
    }

    /// The mark on one item. Turning an item ON is the pick; turning the marked one
    /// OFF is not an answer — there is no "no style" state, since inheriting IS the
    /// answer for that — so it does nothing, the same no-op re-picking the shown
    /// value always was.
    private func pickBinding(for choice: Style?) -> Binding<Bool> {
        Binding(
            get: { options.selection == choice },
            set: { isOn in
                if isOn { pick(choice) }
            }
        )
    }

    /// One core call per outcome, and the outcome is the options' to name. `refused`
    /// is a real answer rather than an error — the chrome can hand over a style this
    /// screen does not draw — and persisting nothing is the honest response, since
    /// the panel would swap that pick out for the fallback anyway.
    private func pick(_ choice: Style?) {
        switch options.write(for: choice) {
        case .clear:
            // Inheriting IS the absence of the key: writing today's declaration into
            // it would look identical this afternoon and then shadow the next
            // declaration forever (docs/DECISIONS.md: global-style-default).
            core.clearStyle(for: screen.id)
        case .override(let style):
            core.setStyle(style, for: screen.id)
        case .refused:
            break
        }
    }

    /// One option's words. Inheriting NAMES the declaration it returns to: "follow
    /// all displays" alone would make the closed control the one place in the pane
    /// that describes a style without saying which, and the section above is where
    /// the reader would have to go to find out.
    private func label(for choice: Style?) -> String {
        guard let choice else {
            return String(
                localized: "settings.general.style.inherit",
                defaultValue: "Follow all displays (\(options.declaration.displayName))"
            )
        }
        return choice.displayName
    }

    /// The sentences this row owes about what is actually on this screen.
    private var footnotes: [String] {
        options.footnotes.map { sentence(for: $0) }
    }

    /// One footnote in words. A `switch` rather than a lookup, so a case added to
    /// the options cannot ship without a sentence: the wording and both its
    /// languages stay in the view, which is the split `DisplayStyleOptions` is
    /// written under.
    private func sentence(for footnote: DisplayStyleOptions.Footnote) -> String {
        switch footnote {
        case .noNotch:
            String(
                localized: "settings.displays.style.footer.noNotch",
                defaultValue: "This display has no notch, so Notch draws as Card here."
            )
        }
    }

    /// The row's title. The built-in panel is named in the app's own vocabulary —
    /// the word the Indicators tab and this section's own footer already use for it,
    /// and one that reads the same in both languages where AppKit's name for it does
    /// not. Every other display carries the name macOS shows, the only name a person
    /// can match against the thing on their desk; the border hands that name over
    /// verbatim and never invents one, so an empty string falls to the generic noun
    /// rather than to an untitled row.
    private var title: String {
        if screen.isInternal {
            return String(localized: "settings.displays.builtIn", defaultValue: "Built-in display")
        }
        return screen.name.isEmpty
            ? String(localized: "settings.displays.unnamed", defaultValue: "Display")
            : screen.name
    }
}
