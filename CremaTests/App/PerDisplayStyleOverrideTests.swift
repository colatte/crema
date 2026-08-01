import Foundation
import Testing
@testable import Crema

/// The Displays tab's raw-value seam: a view reaches the override only through
/// its raw @AppStorage key, so these pin the rule it applies — and that the
/// rule is the store's own, not a second spelling.
struct PerDisplayStyleOverrideTests {
    private let store = EphemeralDefaults()

    @Test func aRetiredRawValueReadsAsInheritsNeverAsAChoice() {
        #expect(PerDisplayStyleOverride.value(fromRawValue: nil) == nil)
        #expect(PerDisplayStyleOverride.value(fromRawValue: "card") == .card)
        // "pill" shipped once and was retired; an override the app can no longer
        // name must read as INHERITS (fall to the declaration), not as a choice.
        #expect(PerDisplayStyleOverride.value(fromRawValue: "pill") == nil)
    }

    @Test func theViewSeamAgreesWithTheStoreOnEveryRawValue() {
        for raw in [nil, "notch", "card", "classic", "pill", ""] {
            #expect(PerDisplayStyleOverride.value(fromRawValue: raw) == Preferences.styleOverride(fromRawValue: raw))
        }
    }

    @Test func existsSpeaksOnlyForTheDisplaysItWasHandedAndIgnoresRetiredValues() {
        let a = ScreenDescription(
            id: DisplayUUID(rawValue: "A"),
            name: "Built-in Retina Display",
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600)),
            isInternal: true
        )
        let b = ScreenDescription(
            id: DisplayUUID(rawValue: "B"),
            name: "LG UltraFine",
            geometry: ScreenGeometry(frame: CGRect(x: 1000, y: 0, width: 1200, height: 800)),
            isInternal: false
        )
        let defaults = store.defaults

        #expect(!PerDisplayStyleOverride.exists(among: [a, b], in: defaults))

        // A retired override is not "a style of its own" — the footer must not
        // warn about a sweep that would change nothing.
        defaults.set("pill", forKey: Preferences.styleKey(for: a.id))
        #expect(!PerDisplayStyleOverride.exists(among: [a, b], in: defaults))

        defaults.set(Style.classic.rawValue, forKey: Preferences.styleKey(for: a.id))
        #expect(PerDisplayStyleOverride.exists(among: [a, b], in: defaults))

        // Scoped to the roster it was handed: an override on a display that is
        // not attached must not raise the warning either.
        #expect(!PerDisplayStyleOverride.exists(among: [b], in: defaults))
    }
}
