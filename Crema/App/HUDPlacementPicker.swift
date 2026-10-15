import SwiftUI

/// Pick where the Card draws its HUD from a native pop-up, each place named and
/// wearing a picture of it (`HUDPlacementIcon`). The pop-up is the system's own
/// control, so keyboard, VoiceOver and the menu's tinting come with it. The
/// picture is a hint; the caller previews the choice on the real HUD
/// (`AppCore.previewHUDPlacement`).
///
/// Offered beside the indicator row, where some display draws Card: the caller
/// owns that gate (docs/DECISIONS.md: rendered-style-gates-settings).
struct HUDPlacementPicker: View {
    /// The persisted rawValue, for the reason `IndicatorPicker.selection` gives:
    /// the caller holds it in `@AppStorage` on the key the panels read.
    @Binding var selection: String

    /// The menu's rows, as the places sit on the glass: the top edge, the middle
    /// of the sides, the bottom edge, each read left to right.
    static let rows: [[HUDPlacement]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    var body: some View {
        Picker(selection: $selection) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider()
                }
                ForEach(row, id: \.self) { placement in
                    Label {
                        Text(placement.displayName)
                    } icon: {
                        Image(nsImage: HUDPlacementIcon.image(for: placement))
                    }
                    .tag(placement.rawValue)
                }
            }
        } label: {
            Text(String(localized: "settings.hud.placement", defaultValue: "Position"))
        }
        .pickerStyle(.menu)
    }
}
