import CoreGraphics
import Testing
@testable import Crema

/// The display order the upgrade migration reads
/// (`AppCore.styleAuthorityOrder`): which legacy per-display override an install
/// that predates the global declaration adopts as it. This order speaks only
/// for the one-time adoption; the all-displays picker reads the declaration key
/// itself (docs/DECISIONS.md: global-style-default). Pure over
/// ScreenDescription values — no AppCore instance, no system API.
///
/// The residual is the one every static seam shares, stated so nobody reads more into it: a
/// mutation that removes the DELEGATION from the instance method is still not caught.
/// (docs/DECISIONS.md: global-style-default)
@MainActor
struct AppCoreStyleAuthorityTests {

    @Test func theAllDisplaysEntryDeclaresGloballyAndSweepsOverrides() {
        // The regression itself, at the only seam that can see it. A body of
        //
        //     for screen in ScreenTranslation.describeAll() { setStyle(_:for:) }
        //
        // writes the ATTACHED displays and nothing else, so a monitor plugged in
        // afterwards resolves to the shipped default under a picker that promises
        // "changes every display at once" — and it leaves an override behind on a
        // detached display, which then outranks the declaration when it comes
        // back (docs/DECISIONS.md: global-style-default).
        //
        // Both assertions are what that loop cannot satisfy: it never writes the
        // global key, and it never touches a display it cannot see.
        let store = EphemeralDefaults()
        let preferences = Preferences(defaults: store.defaults)
        let detached = DisplayUUID(rawValue: "NOT-ATTACHED")
        preferences.setStyle(.classic, for: detached)

        let windows = WindowManagerTests.Harness()
        AppCore.declareStyleEverywhere(.card, in: preferences, applyingTo: windows.manager)

        #expect(preferences.declaredStyle == .card, "the global declaration was never written")
        #expect(preferences.style(for: detached) == .card,
                "a detached display kept an override that now outranks the declaration")
    }

    private static func screen(_ uuid: String, isInternal: Bool) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            name: isInternal ? "Built-in Retina Display" : "LG UltraFine",
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600)),
            isInternal: isInternal
        )
    }

    @Test func theInternalDisplayLeadsAndTheRestKeepTheirOrder() {
        let order = AppCore.styleAuthorityOrder([
            Self.screen("EXT-1", isInternal: false),
            Self.screen("INT", isInternal: true),
            Self.screen("EXT-2", isInternal: false),
        ])

        #expect(order.map(\.rawValue) == ["INT", "EXT-1", "EXT-2"])
    }

    @Test func withNoInternalDisplayTheFirstScreenLeads() {
        let order = AppCore.styleAuthorityOrder([
            Self.screen("EXT-1", isInternal: false),
            Self.screen("EXT-2", isInternal: false),
        ])

        #expect(order.map(\.rawValue) == ["EXT-1", "EXT-2"])
    }
}
