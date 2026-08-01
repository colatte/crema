import CoreGraphics
import Testing
@testable import Crema

/// The composition root's per-display writers and the display reading that feeds
/// them, over the two collaborators a test can build without touching a system
/// API: Preferences on ephemeral defaults and a WindowManager over the fake panel
/// factory (both already assembled by `WindowManagerTests.Harness`).
///
/// No test constructs an `AppCore` — its init boots the real sources — which is
/// why each writer is a static the instance method delegates to, the shape the
/// other wiring seams use. The residual is theirs too, and is stated so nobody
/// reads more into it: a mutation that removes the DELEGATION inside the instance
/// method is still not caught here.
@MainActor
struct AppCorePerDisplayWritersTests {

    private static func screen(
        _ uuid: String,
        isInternal: Bool = false,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    ) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            name: isInternal ? "Built-in Retina Display" : "LG UltraFine",
            geometry: ScreenGeometry(frame: frame),
            isInternal: isInternal
        )
    }

    // MARK: - One reading, two consumers

    @Test func oneScreenReadingFeedsBothThePanelsAndTheSettingsList() {
        // The seam takes an already-read list instead of reading the border
        // itself, and that is what makes "one reading per edge" structural. Two
        // independent readings can differ — a display that left between them — and
        // then the Settings list offers a row for a display no panel carries while
        // a panel draws for a display no row can reach. Two lists disagreeing about
        // which screen is which is the class docs/DECISIONS.md:
        // hud-target-is-a-role rules on.
        let h = WindowManagerTests.Harness()
        let roster = DisplayRoster()
        let builtIn = Self.screen("A", isInternal: true)
        let external = Self.screen("B", frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))

        AppCore.applyScreenRoster([builtIn, external], to: h.manager, mirroring: roster)

        #expect(h.recorder.created.count == 2)
        #expect(roster.displays == [builtIn, external])

        // An unplug moves both sides in the same beat.
        AppCore.applyScreenRoster([builtIn], to: h.manager, mirroring: roster)

        #expect(h.recorder.panel(for: external.id)?.closed == true)
        #expect(roster.displays == [builtIn])
    }

    // MARK: - Style, one display at a time

    @Test func settingOneDisplaysStyleLeavesTheOthersAndTheDeclarationAlone() {
        // The mutation this kills is the tempting "fix": routing a per-display pick
        // through `declareStyleEverywhere`, which is already here and already
        // applies styles live. That one writes the GLOBAL declaration and sweeps
        // every override, so a choice made for one display silently moves the other
        // — and the all-displays picker starts reporting a style the user never
        // declared there (docs/DECISIONS.md: global-style-default).
        let h = WindowManagerTests.Harness()
        let builtIn = Self.screen("A", isInternal: true)
        let external = Self.screen("B", frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))
        h.preferences.declareStyleEverywhere(.card)
        h.manager.updateScreens([builtIn, external])

        AppCore.applyStyleOverride(.classic, on: builtIn.id, in: h.preferences, applyingTo: h.manager)

        #expect(h.preferences.styleOverride(for: builtIn.id) == .classic)
        #expect(h.preferences.styleOverride(for: external.id) == nil)
        #expect(h.preferences.declaredStyle == .card)
        // The live half: only the named display's panel is swapped, and the other
        // one is not even rebuilt — a pass that recreated it would drop its hover
        // monitors for a preference that never spoke about it.
        #expect(h.recorder.created.last(where: { $0.screen.id == builtIn.id })?.style == .classic)
        #expect(h.recorder.created.count == 3)
        #expect(h.recorder.panel(for: external.id)?.closed == false)
    }

    @Test func clearingOneDisplaysStyleSwapsThatPanelBackToTheDeclaredOne() {
        let h = WindowManagerTests.Harness()
        let builtIn = Self.screen("A", isInternal: true)
        h.preferences.declareStyleEverywhere(.card)
        h.preferences.setStyle(.classic, for: builtIn.id)
        h.manager.updateScreens([builtIn])
        #expect(h.recorder.created.last?.style == .classic)

        AppCore.clearStyleOverride(on: builtIn.id, in: h.preferences, applyingTo: h.manager)

        // Inheriting IS the absence of the key: writing today's declaration into it
        // would look identical now and then shadow the next declaration forever,
        // which is the bug the declaration exists to fix.
        #expect(h.preferences.styleOverride(for: builtIn.id) == nil)
        #expect(h.preferences.declaredStyle == .card)
        // And the panel follows in the same beat — a write with no refresh leaves
        // the user looking at the style they just cleared until the next hotplug.
        #expect(h.recorder.created.last(where: { $0.screen.id == builtIn.id })?.style == .card)
        #expect(h.recorder.created.count == 2)
    }

    // MARK: - Show now playing here

    @Test func theShowNowPlayingWriterReachesThePanelsWithoutRecreatingThem() {
        // The pref was live-honoured with no writer for a whole release (the
        // pinned-latent fence P5); this is the writer side of it. Both directions,
        // because a writer that only ever turns the surface OFF is half a control:
        // the internal display defaults on, an external one defaults off, and each
        // has to be able to cross its own default.
        let h = WindowManagerTests.Harness()
        let builtIn = Self.screen("A", isInternal: true)
        h.manager.updateScreens([builtIn])
        #expect(h.recorder.panel(for: builtIn.id)?.showsNowPlayingStates.last == true)
        let created = h.recorder.created.count

        AppCore.applyShowsNowPlaying(false, on: builtIn.id, in: h.preferences, applyingTo: h.manager)
        #expect(h.preferences.showsNowPlaying(on: builtIn.id, isInternal: true) == false)
        #expect(h.recorder.panel(for: builtIn.id)?.showsNowPlayingStates.last == false)

        AppCore.applyShowsNowPlaying(true, on: builtIn.id, in: h.preferences, applyingTo: h.manager)
        #expect(h.recorder.panel(for: builtIn.id)?.showsNowPlayingStates.last == true)

        // Render context, never geometry: the panel carries the flag into its view,
        // so no panel is rebuilt — rebuilding would tear down a live surface and
        // re-arm its hover monitors for a value the view already reads.
        #expect(h.recorder.created.count == created)
    }
}
