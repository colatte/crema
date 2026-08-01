import SwiftUI

/// The declared style, as the submenu of checked items an NSMenu uses to say
/// exactly that. It replaces the status row that spelled the declaration out in a
/// sentence: a checkmark is the platform's word for "this is the one", and unlike
/// the sentence it also lets the user change it from here
/// (docs/DECISIONS.md: menu-status-before-warnings).
///
/// A view of its own, not a branch of CremaMenu's ViewBuilder, for the reason
/// NowPlayingMenuSection is one: SwiftUI tracks observation per BODY, so the
/// declaration read below invalidates this submenu and nothing else. CremaMenu
/// observes the same key on purpose — the fallback row is derived from it — but
/// everything this view adds (the picker's binding, the footnote) stays local.
///
/// No icons on the items. A menu-item icon stands for an OBJECT; a style is a
/// shape the app draws, and a symbol that silently fails to render leaves the row
/// unmarked anyway — the same reason the sentences in this menu carry no glyph.
@MainActor
struct StyleMenu: View {
    let core: AppCore

    /// The key the Settings picker declares into, resolved through Preferences' own
    /// resolver so the shipped default and the degradation of a retired rawValue are
    /// stated once, there. Observed, or the checkmark would sit on the old style
    /// until something unrelated rebuilt this view.
    @AppStorage(Preferences.declaredStyleKey) private var declaredStyle = Preferences.defaultDeclaredStyle.rawValue

    private var title: String {
        String(localized: "menu.style", defaultValue: "Style")
    }

    /// Reads the declaration and writes it back through the app's one all-displays
    /// entry, which also drops the per-display overrides — the same call the
    /// Settings picker makes, so the two cannot mean different things by the same
    /// choice (docs/DECISIONS.md: global-style-default). The write is a click, so
    /// the menu body stays read-only.
    private var selection: Binding<Style> {
        Binding(
            get: { Preferences.declaredStyle(fromRawValue: declaredStyle) },
            set: { core.setStyleEverywhere($0) }
        )
    }

    var body: some View {
        Menu(title) {
            // Inline, so the three options are items of THIS submenu rather than a
            // second one nested inside it: the menu style "presents the options as a
            // menu when the user presses a button, or as a submenu when nested
            // within a larger menu" (SwiftUI, PickerStyle), which is one level too
            // deep for three shapes — and the footnote below has to share the menu
            // the options are in, or it explains nothing.
            Picker(title, selection: selection) {
                ForEach(Style.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.inline)
            Divider()
            // The one consequence the checkmarks cannot show: this declares for every
            // display and sweeps the per-display overrides. Same sentence the
            // Settings footer opens with, word for word — one name per concept, in
            // each language.
            Text(String(localized: "menu.style.appliesEverywhere", defaultValue: "Applies to every display."))
        }
    }
}
