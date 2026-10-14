import CoreGraphics
import SwiftUI

/// The frame rule of the Card's HUD on a panel of its own: the HUD at a placement
/// off the card's own spot, where the card cannot morph into it
/// (docs/DECISIONS.md: card-hud-placement). The panel draws the Card skin's view
/// reading the HUD layer alone, so the HUD is the Card's own drawing; only where
/// it sits is this rule's.
struct CardHUDStyle: PresentationStyle {
    let placement: HUDPlacement

    /// The HUD at its placement; anything else is nothing on this panel, sized
    /// zero on the line the surface hangs from, so show/hide converges there.
    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        let hud = CardStyle.hudFrame(at: placement, on: geometry)
        guard case .hud = state else {
            return CGRect(x: hud.midX, y: hud.maxY, width: 0, height: 0)
        }
        return hud
    }

    /// The HUD has no expanded form to hover into, so the extension's seed — the
    /// compact and expanded frames — is empty here; the hover that matters on
    /// this panel is the one that holds the HUD, around the HUD itself.
    func hoverRegions(on geometry: ScreenGeometry) -> SurfaceHoverRegions? {
        .around(CardStyle.hudFrame(at: placement, on: geometry), margins: hoverExitMargins)
    }

    @MainActor
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> CardView {
        CardView(coordinator: coordinator, displayPolicy: displayPolicy)
    }
}
