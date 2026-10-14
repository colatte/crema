import SwiftUI

/// Where the Card draws the system HUD on its screen: the top centre it shares
/// with the now-playing card, or one of the seven places around the screen's
/// edge. Scoped to the Card the way `HUDIndicatorStyle` is — Notch draws its HUD
/// in the slit and Classic in its bezel.
///
/// Positions on the glass, not in reading order: a screen corner is a place on
/// the desk, and it does not move when the interface language runs right to
/// left.
enum HUDPlacement: String, CaseIterable, Equatable, Sendable {
    /// The placement a Card starts on: the now-playing card's own spot, where
    /// the HUD morphs from it.
    static let shippedDefault: Self = .topCenter

    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    /// The direction the bar runs here: along the edge it sits on. Upright on
    /// the middle of a side; flat along the top and bottom edges, the corners
    /// included — they belong to the edges the menu bar and the Dock run along.
    var axis: Axis {
        switch self {
        case .middleLeft, .middleRight: .vertical
        case .topLeft, .topCenter, .topRight, .bottomLeft, .bottomCenter, .bottomRight: .horizontal
        }
    }
}
