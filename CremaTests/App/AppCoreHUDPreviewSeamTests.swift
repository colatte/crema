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

    @Test func nothingIsReadOrShownWhileTheScreenIsLocked() {
        let h = harness(placement: .bottomLeft)

        AppCore.previewHUDPlacement(lock: MockScreenLockSource(safe: false), displays: h.manager, coordinator: h.base.coordinator)

        #expect(h.base.volumeReading.reads == 0)
        #expect(h.base.coordinator.state == .hidden)
    }

    @Test func nothingIsReadOrShownWhereNoDisplayDrawsCard() {
        let h = WindowManagerTests.Harness()
        h.manager.updateScreens([Self.notchedScreen])

        AppCore.previewHUDPlacement(lock: MockScreenLockSource(safe: true), displays: h.manager, coordinator: h.base.coordinator)

        #expect(h.base.volumeReading.reads == 0)
        #expect(h.base.coordinator.state == .hidden)
    }
}
