import Foundation

/// The per-display style override as a VIEW reads it: from the raw value, which
/// is the only side of the preference an @AppStorage binding can reach
/// (`Preferences.styleKey(for:)` is exposed for exactly that). Same rule as
/// `Preferences.styleOverride(for:)` on the store side — a rawValue a future
/// version retired reads as INHERITS, because it is not a choice the user made
/// and presenting it as one would name a style the app can no longer draw
/// (docs/DECISIONS.md: global-style-default).
enum PerDisplayStyleOverride {
    /// Delegates to the one home of the retired-rawValue rule: a view only
    /// reaches the raw key (@AppStorage), so the store's static is the seam.
    static func value(fromRawValue raw: String?) -> Style? {
        Preferences.styleOverride(fromRawValue: raw)
    }

    /// Whether any of these displays carries a style of its own — the fact the
    /// all-displays footer has to state, since declaring there replaces them all.
    /// One synchronous key read per connected display, on the store @AppStorage
    /// writes: it costs what a row already costs and adds no observation. The
    /// price is a read only as fresh as the body that asks — acceptable because
    /// the sentence is a warning beside the declaration, and the sweep it warns
    /// about happens either way.
    static func exists(among displays: [ScreenDescription], in defaults: UserDefaults = .standard) -> Bool {
        displays.contains { value(fromRawValue: defaults.string(forKey: Preferences.styleKey(for: $0.id))) != nil }
    }
}
