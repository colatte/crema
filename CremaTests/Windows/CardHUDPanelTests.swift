import CoreGraphics
import Testing
@testable import Crema

/// The Card's HUD on a panel of its own: a display drawing Card with the HUD off
/// the card's own spot gets a panel per layer, each drawing only its layer, so the
/// card stays where it is while the HUD shows elsewhere. Moving the HUD rebuilds
/// only the HUD's panel (docs/DECISIONS.md: card-hud-placement).
@MainActor
struct CardHUDPanelTests {

    private static let internalID = DisplayUUID(rawValue: "INTERNAL")
    private static let externalID = DisplayUUID(rawValue: "EXTERNAL")

    /// Notchless, so the default declaration draws Card here.
    private static let internalScreen = ScreenDescription(
        id: internalID,
        name: "Built-in Retina Display",
        geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
        isInternal: true
    )

    private static let externalScreen = ScreenDescription(
        id: externalID,
        name: "LG UltraFine",
        geometry: ScreenGeometry(frame: CGRect(x: 2000, y: 0, width: 2560, height: 1440)),
        isInternal: false
    )

    private static let notchedScreen = ScreenDescription(
        id: DisplayUUID(rawValue: "NOTCHED"),
        name: "Built-in Retina Display",
        geometry: ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32,
            auxLeft: 663.5,
            auxRight: 663.5
        ),
        isInternal: true
    )

    private func harness(placement: HUDPlacement, screens: [ScreenDescription]) -> WindowManagerTests.Harness {
        let h = WindowManagerTests.Harness()
        h.preferences.hudPlacement = placement
        h.manager.updateScreens(screens)
        return h
    }

    private func surfaces(_ h: WindowManagerTests.Harness, on id: DisplayUUID) -> [PanelSurface] {
        h.recorder.created.filter { $0.screen.id == id }.map(\.surface)
    }

    @Test func aCardDisplayWithItsHUDOffItsSpotGetsAPanelPerLayer() {
        let h = harness(placement: .bottomRight, screens: [Self.externalScreen, Self.notchedScreen])

        #expect(surfaces(h, on: Self.externalID) == [.cardNowPlaying, .cardHUD(.bottomRight)])
        // The notch draws its HUD in the slit: the placement is the Card's alone.
        #expect(surfaces(h, on: Self.notchedScreen.id) == [.skin(.notch)])
    }

    @Test func movingTheHUDRebuildsOnlyItsPanel() throws {
        let h = harness(placement: .topCenter, screens: [Self.externalScreen])
        let shared = try #require(h.recorder.panel(for: Self.externalID))
        #expect(surfaces(h, on: Self.externalID) == [.skin(.card)])

        h.preferences.hudPlacement = .bottomLeft
        h.manager.refreshStyles()
        #expect(shared.closed)
        let card = try #require(h.recorder.panel(for: Self.externalID))
        let firstHUD = try #require(h.recorder.hudPanel(for: Self.externalID))

        h.preferences.hudPlacement = .middleRight
        h.manager.refreshStyles()
        #expect(firstHUD.closed)
        #expect(!card.closed)
        #expect(h.recorder.panel(for: Self.externalID) === card)
        #expect(surfaces(h, on: Self.externalID).last == .cardHUD(.middleRight))

        h.preferences.hudPlacement = .topCenter
        h.manager.refreshStyles()
        #expect(card.closed)
        #expect(h.recorder.hudPanel(for: Self.externalID)?.closed == true)
        #expect(surfaces(h, on: Self.externalID).last == .skin(.card))
    }

    @Test func theCardStaysOnItsSpotWhileTheHUDShowsOnItsOwn() async throws {
        // The internal display: now playing is on there by default.
        let h = harness(placement: .middleLeft, screens: [Self.internalScreen])
        let geometry = Self.internalScreen.geometry
        let card = try #require(h.recorder.panel(for: Self.internalID))
        let hudPanel = try #require(h.recorder.hudPanel(for: Self.internalID))

        let track = CoordinatorHarness.playingTrack()
        h.base.nowPlayingSource.emit(track)
        let compact = Style.card.frame(for: .nowPlaying(track, expanded: false), on: geometry)
        #expect(await eventually { card.appliedFrames.last == compact })
        #expect(hudPanel.appliedFrames.last?.isEmpty == true)
        #expect(hudPanel.hoverArmedStates.last == false)

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.base.hudSource.emit(hud)
        #expect(await eventually { hudPanel.appliedFrames.last == CardStyle.hudFrame(at: .middleLeft, on: geometry) })
        #expect(hudPanel.hoverArmedStates.last == true)
        #expect(hudPanel.showsHUDStates.last == true)
        // The card is not covered: its panel still draws the appearance.
        #expect(card.appliedFrames.last == compact)
        #expect(card.hoverArmedStates.last == true)
    }

    @Test func aHUDForAnotherDisplayStaysOffThisDisplaysHUDPanel() async throws {
        let h = harness(placement: .bottomCenter, screens: [Self.internalScreen, Self.externalScreen])
        let internalHUD = try #require(h.recorder.hudPanel(for: Self.internalID))
        let externalHUD = try #require(h.recorder.hudPanel(for: Self.externalID))

        let hud = SystemHUD(
            kind: .screenBrightness, value: 0.4, target: .display(Self.externalID), authority: .betterDisplay
        )
        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(externalHUD.appliedFrames.last == CardStyle.hudFrame(at: .bottomCenter, on: Self.externalScreen.geometry))
        #expect(externalHUD.showsHUDStates.last == true)
        #expect(internalHUD.appliedFrames.last?.isEmpty == true)
        #expect(internalHUD.showsHUDStates.last == false)
    }

    @Test func eachPanelsHoverReachesTheLayerItDraws() async {
        // The monitor's callback, through the dispatch it runs: the HUD's own
        // panel holds the HUD and expands nothing; the card's panel expands the
        // card and never holds the HUD.
        let base = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        base.nowPlayingSource.emit(track)
        #expect(await eventually { base.coordinator.state == .nowPlaying(track, expanded: false) })
        let hud = SystemHUD(kind: .volume, value: 0.5)
        base.hudSource.emit(hud)
        #expect(await eventually { base.coordinator.layers.hud == hud })
        await base.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)

        NSPanelPresentationPanel.forwardHover(true, from: .cardNowPlaying, to: base.coordinator)
        #expect(base.coordinator.layers.nowPlaying?.expanded == true)
        #expect(base.clock.pendingSleeps == 1)   // the revert still runs
        NSPanelPresentationPanel.forwardHover(false, from: .cardNowPlaying, to: base.coordinator)

        NSPanelPresentationPanel.forwardHover(true, from: .cardHUD(.bottomRight), to: base.coordinator)
        #expect(base.clock.pendingSleeps == 0)   // the HUD is held
        #expect(base.coordinator.layers.nowPlaying?.expanded == false)
    }

    @Test(arguments: [true, false])
    func aPanelLeavingADisplayThatStaysReceivesNothingFromThePassItsCloseReenters(movesTheHUD: Bool) {
        // The other seam that closes panels: the display stays, its HUD's panel
        // goes — moved, or rebuilt for a new geometry. The roster must drop it
        // before the close re-enters a frame pass, or that pass re-arms a closed
        // panel's monitors (docs/DECISIONS.md:
        // a-panel-leaves-the-roster-before-it-closes).
        let base = CoordinatorHarness()
        let store = EphemeralDefaults()
        let preferences = Preferences(defaults: store.defaults)
        preferences.hudPlacement = .bottomRight
        let reentering = WindowManagerTests.ReenteringPanel()
        var handedOut = false
        let manager = WindowManager(coordinator: base.coordinator, preferences: preferences) { _, surface, _ in
            guard surface.layers == .hud, !handedOut else { return RecordingPanel() }
            handedOut = true
            return reentering
        }
        manager.start()
        manager.updateScreens([Self.internalScreen])
        reentering.onClose = { manager.refreshPresentation() }

        if movesTheHUD {
            preferences.hudPlacement = .topLeft
            manager.refreshStyles()
        } else {
            manager.updateScreens([ScreenDescription(
                id: Self.internalID,
                name: Self.internalScreen.name,
                geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900)),
                isInternal: true
            )])
        }

        #expect(reentering.isClosed)
        #expect(reentering.appliesAfterClose == 0)
    }

    @Test func aDisplayThatLeavesTakesBothItsPanels() throws {
        let h = harness(placement: .topLeft, screens: [Self.internalScreen, Self.externalScreen])
        let card = try #require(h.recorder.panel(for: Self.externalID))
        let hudPanel = try #require(h.recorder.hudPanel(for: Self.externalID))

        h.manager.updateScreens([Self.internalScreen])

        #expect(card.closed)
        #expect(hudPanel.closed)
        #expect(h.recorder.hudPanel(for: Self.internalID)?.closed == false)
    }

    @Test func aGeometryChangeRebuildsBothPanels() throws {
        let h = harness(placement: .bottomRight, screens: [Self.externalScreen])
        let card = try #require(h.recorder.panel(for: Self.externalID))
        let hudPanel = try #require(h.recorder.hudPanel(for: Self.externalID))

        let rescaled = ScreenDescription(
            id: Self.externalID,
            name: Self.externalScreen.name,
            geometry: ScreenGeometry(frame: CGRect(x: 2000, y: 0, width: 1920, height: 1080)),
            isInternal: false
        )
        h.manager.updateScreens([rescaled])

        #expect(card.closed)
        #expect(hudPanel.closed)
        #expect(surfaces(h, on: Self.externalID).suffix(2) == [.cardNowPlaying, .cardHUD(.bottomRight)])
    }
}
