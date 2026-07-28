import Foundation

/// The appearance of the shared HUD level indicator (volume / screen and
/// keyboard brightness), chosen in Settings and scoped to the Card style —
/// Notch always renders the capsule and Classic its segmented bar. Like Style,
/// an enum whose raw value is the Preferences persistence format, so an
/// unknown persisted rawValue degrades to `.slider` (the shipped default)
/// rather than crashing.
enum HUDIndicatorStyle: String, CaseIterable, Equatable, Sendable {
    /// The native-style capsule track (HUDLevelSlider.Appearance.capsule). The
    /// rawValue keeps the retired stock-Slider body's name — it is persisted,
    /// so renaming it would silently reset users' choice.
    case slider
    /// iOS-style full bleed: the whole bar is the fill (Card only).
    case filled

    /// User-facing name (String Catalog; English as source language).
    var displayName: String {
        switch self {
        case .slider:
            String(localized: "settings.hud.indicator.slider", defaultValue: "Line")
        case .filled:
            String(localized: "settings.hud.indicator.filled", defaultValue: "Filled")
        }
    }
}
