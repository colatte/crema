import CoreGraphics
import Testing
@testable import Crema

/// The single display order both style readers share
/// (`AppCore.styleAuthorityOrder`): the value the all-displays picker shows and
/// the legacy override an upgrade adopts as the global declaration. If the two
/// disagreed, an upgrade would adopt a style the picker never displayed. Pure
/// over ScreenDescription values — no AppCore instance, no system API.
///
/// Known gap, measured: nothing pins `AppCore.setStyleEverywhere` actually
/// CALLING `declareStyleEverywhere`. Replacing that one line with the old
/// `for screen in ScreenTranslation.describeAll() { setStyle(_:for:) }` leaves
/// this suite, PreferencesTests and WindowManagerTests all green — the whole
/// regression the declaration was introduced to end, and no test sees it. It is
/// not fixable at this seam: reaching that method means constructing `AppCore`,
/// which boots the real system sources a unit test may never touch. What IS
/// pinned is everything on either side — the order chosen here, and every
/// resolution and sweep rule in PreferencesTests.
/// (docs/DECISIONS.md: global-style-default)
@MainActor
struct AppCoreStyleAuthorityTests {

    private static func screen(_ uuid: String, isInternal: Bool) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
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
