import CoreGraphics
import Testing
@testable import Crema

/// The single display order both style readers share
/// (`AppCore.styleAuthorityOrder`): the value the all-displays picker shows and
/// the legacy override an upgrade adopts as the global declaration. If the two
/// disagreed, an upgrade would adopt a style the picker never displayed. Pure
/// over ScreenDescription values — no AppCore instance, no system API.
///
/// The gap this file used to declare unfixable is closed, and the declaration was
/// wrong: "reaching that method means constructing AppCore" is true of the INSTANCE
/// method, and the repository already had five answers to that exact problem —
/// `wireActiveSourceEnded`, the three `wire*Reinstall`, `reconcileLoginItemIntent`,
/// all extracted as statics over constructible collaborators. `declareStyleEverywhere`
/// is now the sixth, and `theAllDisplaysEntryDeclaresGloballyAndSweepsOverrides`
/// below kills the old per-display loop.
/// The residual is the one all six share, stated so nobody reads more into it: a
/// mutation that removes the DELEGATION from the instance method is still not caught.
/// (docs/DECISIONS.md: global-style-default)
@MainActor
struct AppCoreStyleAuthorityTests {

    @Test func theAllDisplaysEntryDeclaresGloballyAndSweepsOverrides() {
        // The regression itself, at the only seam that can see it. The old body
        //
        //     for screen in ScreenTranslation.describeAll() { setStyle(_:for:) }
        //
        // wrote the ATTACHED displays and nothing else, so a monitor plugged in
        // afterwards resolved to the shipped default under a picker that promises
        // "applies to every display" — and it left an override behind on a display
        // that had been detached, which then outranked the declaration when it came
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
