import CoreGraphics
import SwiftUI

/// What one panel draws. A skin draws both layers on one panel, except the Card
/// with its HUD placed off the card's own spot: there the card and its HUD are two
/// panels, each drawing one layer (docs/DECISIONS.md: card-hud-placement). The
/// closed set of panels, dispatched by switch like `Style`: the frame rules'
/// overrides are extension methods, which an existential would bypass.
enum PanelSurface: Hashable, Sendable {
    /// A skin's own panel, both layers on it.
    case skin(Style)
    /// The Card's now-playing alone, its HUD on a panel of its own.
    case cardNowPlaying
    /// The Card's HUD alone, at a placement off the card's spot.
    case cardHUD(HUDPlacement)

    /// The panels a display rendering `style` gets. Only the Card's HUD moves, and
    /// on the card's own spot the card morphs into it on one panel.
    static func surfaces(for style: Style, hudPlacement: HUDPlacement) -> [Self] {
        guard style == .card, hudPlacement != HUDPlacement.cardsOwnSpot else { return [.skin(style)] }
        return [.cardNowPlaying, .cardHUD(hudPlacement)]
    }

    /// The skin this panel belongs to.
    var style: Style {
        switch self {
        case .skin(let style): style
        case .cardNowPlaying, .cardHUD: .card
        }
    }

    /// The layers this panel draws, and the surface its pointer events name.
    var layers: PresentationLayers.Surface {
        switch self {
        case .skin: .both
        case .cardNowPlaying: .nowPlaying
        case .cardHUD: .hud
        }
    }

    /// Whether this panel's frame rule reads the Dock's room. Only the Card's HUD
    /// on its own panel keeps its margin from where the Dock ends; every other
    /// surface hangs from the top or keeps its own height, so a Dock that moves or
    /// hides changes nothing it captured.
    var readsTheDock: Bool {
        if case .cardHUD = self {
            true
        } else {
            false
        }
    }

    /// The direction this panel's HUD bar runs.
    var hudAxis: Axis {
        switch self {
        case .skin, .cardNowPlaying: .horizontal
        case .cardHUD(let placement): placement.axis
        }
    }

    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        switch self {
        case .skin, .cardNowPlaying: style.frame(for: state, on: geometry)
        case .cardHUD(let placement): CardHUDStyle(placement: placement).frame(for: state, on: geometry)
        }
    }

    func windowFrame(on geometry: ScreenGeometry) -> CGRect {
        switch self {
        case .skin, .cardNowPlaying: style.windowFrame(on: geometry)
        case .cardHUD(let placement): CardHUDStyle(placement: placement).windowFrame(on: geometry)
        }
    }

    func hoverRegions(on geometry: ScreenGeometry) -> SurfaceHoverRegions? {
        switch self {
        case .skin, .cardNowPlaying: style.hoverRegions(on: geometry)
        case .cardHUD(let placement): CardHUDStyle(placement: placement).hoverRegions(on: geometry)
        }
    }

    func stateSizes(on geometry: ScreenGeometry) -> SurfaceStateSizes? {
        switch self {
        case .skin, .cardNowPlaying: style.stateSizes(on: geometry)
        case .cardHUD(let placement): CardHUDStyle(placement: placement).stateSizes(on: geometry)
        }
    }

    /// Nil on the HUD's own panel: a click there has no appearance to invoke.
    func invokeZone(on geometry: ScreenGeometry) -> CGRect? {
        switch self {
        case .skin, .cardNowPlaying: style.invokeZone(on: geometry)
        case .cardHUD: nil
        }
    }

    var hoverExitMargins: SurfaceHoverRegions.Margins {
        switch self {
        case .skin, .cardNowPlaying: style.hoverExitMargins
        case .cardHUD(let placement): CardHUDStyle(placement: placement).hoverExitMargins
        }
    }

    /// The skin's: the Card's HUD hangs from the top of its own window too, and
    /// commits its hover at once like the card.
    var surfaceVerticalAnchor: SurfaceVerticalAnchor { style.surfaceVerticalAnchor }
    /// Room the window keeps above the surface it hangs from its top: an upright
    /// Card HUD's, for the pull past the bar's top end; none anywhere else.
    var surfaceTopInset: CGFloat { CardMetrics.hudTopHeadroom(for: hudAxis) }
    var hoverCommit: Style.HoverCommit { style.hoverCommit }

    /// The skin's own view, reading the layers `displayPolicy` names.
    @MainActor @ViewBuilder
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> some View {
        switch self {
        case .skin, .cardNowPlaying:
            style.makeView(coordinator: coordinator, displayPolicy: displayPolicy)
        case .cardHUD(let placement):
            CardHUDStyle(placement: placement).makeView(coordinator: coordinator, displayPolicy: displayPolicy)
        }
    }
}
