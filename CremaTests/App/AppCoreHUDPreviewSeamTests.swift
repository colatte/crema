import CoreGraphics
import Testing
@testable import Crema

/// The placement preview through the production seam (`AppCore.previewHUDPlacement`)
/// and the real WindowManager: drawn by every display drawing Card, by no other,
/// and by none while the screen is locked (docs/DECISIONS.md: card-hud-placement).
@MainActor
struct AppCoreHUDPreviewSeamTests {

    private static let cardID = DisplayUUID(rawValue: "EXTERNAL")
    private static let notchID = DisplayUUID(rawValue: "NOTCHED")

    /// Notchless, so the default declaration draws Card here.
    private static let cardScreen = ScreenDescription(
        id: cardID,
        name: "LG UltraFine",
        geometry: ScreenGeometry(frame: CGRect(x: 2000, y: 0, width: 2560, height: 1440)),
        isInternal: false
    )

    private static let notchedScreen = ScreenDescription(
        id: notchID,
        name: "Built-in Retina Display",
        geometry: ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32,
            auxLeft: 663.5,
            auxRight: 663.5
        ),
        isInternal: true
    )

    private func harness(placement: HUDPlacement) -> WindowManagerTests.Harness {
        let h = WindowManagerTests.Harness()
        h.preferences.hudPlacement = placement
        h.manager.updateScreens([Self.cardScreen, Self.notchedScreen])
        return h
    }

    @Test func thePreviewIsDrawnByTheCardsHUDPanelAndNotByTheNotch() async throws {
        let h = harness(placement: .bottomLeft)
        let level = try #require(h.base.volumeReading.reading)

        AppCore.previewHUDPlacement(lock: MockScreenLockSource(safe: true), displays: h.manager, coordinator: h.base.coordinator)

        #expect(await eventually { h.base.coordinator.state == .hud(level) })
        let cardHUD = try #require(h.recorder.hudPanel(for: Self.cardID))
        let expected = CardStyle.hudFrame(at: .bottomLeft, on: Self.cardScreen.geometry)
        #expect(cardHUD.appliedFrames.last == expected)
        #expect(cardHUD.showsHUDStates.last == true)
        // A volume key would draw the notch's own bar too; the preview is of the
        // Card's place, so the notch shows nothing for it.
        let notch = try #require(h.recorder.panel(for: Self.notchID))
        #expect(notch.showsHUDStates.last == false)
        #expect(notch.appliedFrames.last == Style.notch.frame(for: .hidden, on: Self.notchedScreen.geometry))
    }

    @Test func choosingAPlacePersistsItBuildsItsPanelAndPreviewsThere() async throws {
        // From the card's own spot to a corner: the choice is saved, the Card
        // display gains the HUD panel for that corner, and the preview is drawn
        // by that panel at that corner.
        let h = harness(placement: .topCenter)
        let level = try #require(h.base.volumeReading.reading)
        #expect(h.recorder.hudPanel(for: Self.cardID) == nil)

        AppCore.chooseHUDPlacement(
            .bottomRight,
            preferences: h.preferences,
            lock: MockScreenLockSource(safe: true),
            windowManager: h.manager,
            coordinator: h.base.coordinator
        )

        #expect(h.preferences.hudPlacement == .bottomRight)
        #expect(await eventually { h.base.coordinator.state == .hud(level) })
        let cardHUD = try #require(h.recorder.hudPanel(for: Self.cardID))
        #expect(cardHUD.appliedFrames.last == CardStyle.hudFrame(at: .bottomRight, on: Self.cardScreen.geometry))
        #expect(cardHUD.showsHUDStates.last == true)
    }

    // The read a preview makes runs on a task of its own, so a refusal is only
    // proven once that task has had the window to run: a check right after the
    // call would pass even with the gate gone.

    @Test func nothingIsReadOrShownWhileTheScreenIsLocked() async {
        let h = harness(placement: .bottomLeft)

        AppCore.previewHUDPlacement(lock: MockScreenLockSource(safe: false), displays: h.manager, coordinator: h.base.coordinator)

        #expect(await !footprintAppears { h.base.volumeReading.reads > 0 || h.base.coordinator.state != .hidden })
    }

    @Test func nothingIsReadOrShownWhereNoDisplayDrawsCard() async {
        let h = WindowManagerTests.Harness()
        h.manager.updateScreens([Self.notchedScreen])

        AppCore.previewHUDPlacement(lock: MockScreenLockSource(safe: true), displays: h.manager, coordinator: h.base.coordinator)

        #expect(await !footprintAppears { h.base.volumeReading.reads > 0 || h.base.coordinator.state != .hidden })
    }
}
