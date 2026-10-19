/// One of a neighbour app's feedback switches that Crema takes over while it
/// replaces the system indicators. Named for what the switch does, never for the
/// neighbour's key: the wire name is translated at the edge.
///
/// The declaration order is the take-over's: dispatch goes on before the
/// neighbour's own indicator goes off, so no press in between is left with
/// neither. Handing back walks it in reverse, for the same reason.
enum NeighbourOSDSetting: String, CaseIterable, Sendable {
    /// The neighbour posts each adjustment for another app to draw.
    case dispatchesToOtherApps
    /// The neighbour draws its own brightness, volume and mute indicator.
    case showsOwnIndicator

    /// What the switch reads while Crema holds the feedback.
    var heldValue: Bool {
        switch self {
        case .dispatchesToOtherApps: true
        case .showsOwnIndicator: false
        }
    }
}
