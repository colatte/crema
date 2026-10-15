import AppKit
import SwiftUI

/// The Card's indicator and where it sits, in a section of its own after the
/// display rows.
///
/// It lives on the General tab rather than in the Indicators tab because each
/// choice is a picture of a bar, and the picture means something next to the
/// displays drawing the surface the bar sits on. After them, not under the style
/// tiles: there, in a mixed setup, it is a Card control under a selected Notch,
/// with nothing saying which display it is for (docs/DECISIONS.md:
/// global-style-default).
struct CardIndicatorSection: View {
    let core: AppCore
    let wallpaper: NSImage?
    /// The displays drawing Card, named the way the rows above name them.
    let displayNames: String
    /// On the same persisted keys the panels read.
    @AppStorage(Preferences.hudIndicatorStyleKey) private var indicatorStyle = HUDIndicatorStyle.shippedDefault.rawValue
    @AppStorage(Preferences.hudPlacementKey) private var placement = HUDPlacement.shippedDefault.rawValue

    var body: some View {
        Section {
            LabeledContent {
                IndicatorPicker(selection: $indicatorStyle, wallpaper: wallpaper)
            } label: {
                Text(String(localized: "settings.hud.indicator", defaultValue: "Card indicator"))
            }
            .onChange(of: indicatorStyle) { _, new in
                core.setHUDIndicatorStyle(HUDIndicatorStyle(rawValue: new) ?? .shippedDefault)
            }
            HUDPlacementPicker(selection: $placement)
                .onChange(of: placement) { _, new in
                    core.chooseHUDPlacement(HUDPlacement(rawValue: new) ?? .shippedDefault)
                }
        } footer: {
            // Names the displays, because this is the one control in the pane that
            // is not per display: without the names, a Card setting under a Notch
            // declaration reads as belonging to Notch.
            Text(String(
                localized: "settings.hud.indicator.footer",
                defaultValue: "Displays drawing Card: \(displayNames)."
            ))
            .settingsFootnote()
        }
    }
}
