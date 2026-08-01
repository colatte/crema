import Foundation

/// What one display's style control offers, what it reads back, and what a pick
/// is allowed to write — derived from the two raw preference values and that
/// screen's geometry, so the chrome around it only draws.
///
/// The refusal cannot live in the popup. Measured on macOS 26.5.2
/// (`scripts/probes/picker-option-disabled.swift`): a SwiftUI `Picker` in `.menu`
/// style DISCARDS `.disabled` on its options — the marked item read back
/// `isEnabled == true` against an `NSPopUpButton` control reading `false` — so a
/// style this screen cannot draw stays clickable there no matter what the chrome
/// asks for. `write(for:)` is what keeps such a pick out of the store; a custom
/// `Menu` of one item per option, where `.disabled` IS honoured, is only what
/// keeps it out of reach.
///
/// Nothing here knows a string: the view maps each case to its localized
/// sentence, the same split `MenuStatus` lives under.
struct DisplayStyleOptions {
    /// One row of the list: a style, or inheriting the declaration (`nil`). The
    /// enablement travels WITH the choice — handed out as a bare list of styles,
    /// every reader would re-derive which ones this screen draws, and the one that
    /// forgets offers a pick the panel silently swaps out.
    struct Item: Equatable {
        let choice: Style?
        let isEnabled: Bool
    }

    /// What a pick does to this display's key. `refused` is an outcome and not an
    /// error: the chrome can hand over a style this screen cannot draw, and the
    /// honest answer is to write nothing rather than persist a choice the panel
    /// would swap out for the fallback.
    enum Write: Equatable {
        /// Remove the key. Inheriting IS its absence — a copy of today's
        /// declaration written into it would look identical this afternoon and then
        /// shadow the next declaration forever
        /// (docs/DECISIONS.md: global-style-default).
        case clear
        case override(Style)
        case refused
    }

    /// A sentence the control owes about what is actually happening on this
    /// screen. A case rather than a string, so the wording and both its languages
    /// stay in the view.
    enum Footnote: Equatable {
        /// The style in force here is the notch skin and this panel has no slit, so
        /// what is drawn is the card. Stated as a fact in effect, never as a
        /// hypothetical: a sentence about a fallback that is not happening reads as
        /// a warning about the style just picked.
        case noNotch
    }

    /// This display's own choice, or nil when it inherits. Never resolved away and
    /// never filtered by what the screen draws: an override this panel does not
    /// honour is still the choice the user made, and the list shows it selected AND
    /// disabled — the honest report of "you chose this and this screen does not
    /// draw it" (docs/DECISIONS.md: selected-and-disabled-is-a-state).
    let selection: Style?
    /// What the all-displays section declared — the fallback this display returns
    /// to, and the only thing inheriting can mean.
    let declaration: Style
    /// The style in force on this display: its own if it has one, else the
    /// declaration. Asked of the resolver the panels render by, because a second
    /// copy of that rule is how a control comes to name a style its screen does not
    /// draw. It is the CHOSEN style, not necessarily the drawn one — `footnotes` is
    /// where that difference is spoken.
    let effectiveStyle: Style
    private let geometry: ScreenGeometry

    init(overrideRawValue: String?, declaredRawValue: String?, geometry: ScreenGeometry) {
        selection = Preferences.styleOverride(fromRawValue: overrideRawValue)
        declaration = Preferences.declaredStyle(fromRawValue: declaredRawValue)
        effectiveStyle = Preferences.style(overrideRawValue: overrideRawValue, declaredRawValue: declaredRawValue)
        self.geometry = geometry
    }

    /// The list in the order it is read: inheriting first, then the styles in their
    /// declared order. Inherit leads because it is the answer this display gives
    /// before it is given one — a list that opens on a style opens on a choice
    /// nobody made.
    var items: [Item] {
        [item(for: nil)] + Style.allCases.map { item(for: $0) }
    }

    /// What this control has to say about what is on this screen, gated on the
    /// style in FORCE rather than on there being an override. The common case is a
    /// display inheriting a Notch declaration it cannot draw — the shipped default,
    /// on every Mac without a slit — and a gate on the override would go silent
    /// exactly there while speaking up where an override already says Card.
    var footnotes: [Footnote] {
        effectiveStyle.isHonoured(on: geometry) ? [] : [.noNotch]
    }

    /// Whether this screen draws that style as picked instead of the fallback
    /// standing in for it — one resolver answers it (`Style.isHonoured`), the same
    /// one the panels and the thumbnails ask, so the list cannot offer a style the
    /// screen would swap out (docs/DECISIONS.md: rendered-style-gates-settings).
    /// Inheriting is always offered: a display can END UP on a style this panel
    /// does not draw, by inheriting a declaration, but it is never PUT there here.
    func isEnabled(_ choice: Style?) -> Bool {
        guard let choice else { return true }
        return choice.isHonoured(on: geometry)
    }

    /// What picking `choice` does to this display's key. Nil is the return to the
    /// declaration, the one answer no geometry can refuse — the declaration exists
    /// for every screen, whatever each one draws of it.
    func write(for choice: Style?) -> Write {
        guard let choice else { return .clear }
        guard isEnabled(choice) else { return .refused }
        return .override(choice)
    }

    private func item(for choice: Style?) -> Item {
        Item(choice: choice, isEnabled: isEnabled(choice))
    }

    /// Whether the per-display list is offered at all. Not a count of screens: the
    /// question is whether there is an answer per display that the all-displays
    /// section above cannot give, and each clause below is one way there is one.
    static func listIsOffered(for displays: [ScreenDescription], in defaults: UserDefaults = .standard) -> Bool {
        // More than one screen is the only arrangement in which per-display answers
        // can differ from each other at all.
        if displays.count > 1 { return true }
        guard let only = displays.first else { return false }
        // A sole EXTERNAL panel — the Mac mini, the Studio, the clamshell desk:
        // `Preferences.defaultShowsNowPlaying(isInternal:)` is literally
        // `isInternal`, so the now-playing surface is born off there and no other
        // control in the app can turn it on.
        if !only.isInternal { return true }
        // A key written when more displays were attached outlives that arrangement:
        // without a row nothing can clear it, while the sweep footnote above goes on
        // naming a per-display style the user has no way to see.
        return PerDisplayStyleOverride.exists(among: displays, in: defaults)
    }
}
