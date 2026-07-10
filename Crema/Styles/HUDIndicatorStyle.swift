import Foundation

/// The appearance of the shared HUD level indicator (volume / screen and
/// keyboard brightness), chosen in Settings and scoped to the Card style —
/// Notch and Classic always render the slider. Like Style, an enum whose raw
/// value is the Preferences persistence format, so an unknown persisted
/// rawValue degrades to `.slider` (the shipped default) rather than crashing.
enum HUDIndicatorStyle: String, CaseIterable, Equatable, Sendable {
    /// The system slider with a draggable thumb — every skin's default.
    case slider
    /// iOS-style: the whole bar is the fill, no thumb (Card only).
    case filled

    /// User-facing name (String Catalog; English as source language).
    var displayName: String {
        switch self {
        case .slider:
            String(localized: "settings.hud.indicator.slider", defaultValue: "Slider")
        case .filled:
            String(localized: "settings.hud.indicator.filled", defaultValue: "Filled bar")
        }
    }
}
