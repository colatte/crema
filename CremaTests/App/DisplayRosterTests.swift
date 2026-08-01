import CoreGraphics
import Observation
import Testing
@testable import Crema

/// The roster the per-display Settings list reads: what is connected, in the
/// border's own words, published as the panels are built from the same reading.
///
/// The three claims here are the three the list rests on — it is REACTIVE (the
/// General tab's mirrors are seeded once by decision, and a list whose rows ARE
/// the displays cannot afford that), an unchanged topology is not a change, and
/// every row is answerable from the value alone.
@MainActor
struct DisplayRosterTests {

    private static func screen(
        _ uuid: String,
        name: String,
        isInternal: Bool = false,
        geometry: ScreenGeometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    ) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            name: name,
            geometry: geometry,
            isInternal: isInternal
        )
    }

    @Test func theRosterStartsEmptyAndPublishesTheListItWasHanded() {
        let roster = DisplayRoster()
        #expect(roster.displays.isEmpty)

        let builtIn = Self.screen("A", name: "Built-in Retina Display", isInternal: true)
        let external = Self.screen("B", name: "LG UltraFine")
        roster.update([builtIn, external])

        #expect(roster.displays == [builtIn, external])

        // Each reading REPLACES the roster rather than merging into it: a display
        // that left must lose its row, and a row for a monitor that is gone offers
        // a control over a screen the user cannot see.
        roster.update([external])
        #expect(roster.displays == [external])
    }

    @Test func aRealTopologyChangeNotifiesAndAnIdenticalListDoesNot() async {
        // Honest about what this can and cannot detect, the same way the menu
        // mirrors' suite is: the house measured that an equal-value write to an
        // @Observable property invalidates nothing on its own, so this does not
        // catch the removal of the guard in `update`. What it pins is the
        // CONTRACT the Settings list depends on — a hotplug moves it, and a
        // re-reading of the same topology leaves every open view alone.
        // `didChangeScreenParameters` fires for far more than hotplugs (a
        // resolution change, a display waking), so "same list, no news" is the
        // common case, not the rare one.
        let roster = DisplayRoster()
        let builtIn = Self.screen("A", name: "Built-in Retina Display", isInternal: true)
        roster.update([builtIn])

        let changed = Flag()
        withObservationTracking {
            _ = roster.displays
        } onChange: {
            changed.value = true
        }

        roster.update([builtIn])
        await settle()
        #expect(!changed.value)

        roster.update([builtIn, Self.screen("B", name: "LG UltraFine")])

        #expect(await eventually { changed.value })
        #expect(roster.displays.count == 2)
    }

    @Test func theRosterCarriesGeometryAndNameSoTheTabNeverAsksTheSystem() {
        // Everything a per-display row needs travels inside the value: the name
        // macOS itself shows for the display, the geometry that decides whether
        // the notch skin is drawable there, and whether it is the built-in panel
        // (the "show now playing here" default). A row that asked NSScreen for any
        // of it would be reading a SECOND list, which is how a row ends up
        // describing a display the panels resolved differently.
        let notched = Self.screen(
            "N",
            name: "Built-in Retina Display",
            isInternal: true,
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeTop: 32,
                auxLeft: 663.5,
                auxRight: 663.5
            )
        )
        let external = Self.screen("EXT", name: "LG UltraFine")
        let roster = DisplayRoster()

        roster.update([notched, external])

        #expect(roster.displays.map(\.name) == ["Built-in Retina Display", "LG UltraFine"])
        #expect(roster.displays.map(\.isInternal) == [true, false])
        // Order is the border's, carried verbatim — the list a user reads top to
        // bottom must not reshuffle between readings.
        #expect(roster.displays.map(\.id) == [notched.id, external.id])
        // The render question, answered from the row alone: the same resolver the
        // panels are built through, with no system call in between.
        #expect(roster.displays.map { Style.notch.resolved(on: $0.geometry) } == [.notch, .card])
    }
}
