import CoreGraphics
import Testing
@testable import Crema

/// Which display shows a HUD. The app has one state and one panel per screen, so
/// this is where a bar for a particular display stops being a bar on every
/// display — and stops being a control for a screen the user is not looking at
/// (docs/DECISIONS.md: hud-belongs-to-its-display).
@MainActor
struct PerDisplayHUDTests {

    private static let internalID = DisplayUUID(rawValue: "INTERNAL")
    private static let externalID = DisplayUUID(rawValue: "EXTERNAL")

    private static func internalScreen() -> ScreenDescription {
        ScreenDescription(
            id: internalID,
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            isInternal: true
        )
    }

    private static func externalScreen() -> ScreenDescription {
        ScreenDescription(
            id: externalID,
            geometry: ScreenGeometry(frame: CGRect(x: 2000, y: 0, width: 2560, height: 1440)),
            isInternal: false
        )
    }

    /// Both screens are notchless, so the default style resolves to card on each.
    private static func frame(_ state: PresentationState, on screen: ScreenDescription) -> CGRect {
        Style.card.frame(for: state, on: screen.geometry)
    }

    private func makeHarness() -> WindowManagerTests.Harness {
        let h = WindowManagerTests.Harness()
        h.manager.updateScreens([Self.internalScreen(), Self.externalScreen()])
        return h
    }

    @Test func aHUDNamingNoDisplayShowsEverywhere() async {
        // Volume belongs to no display at all, and the built-in brightness reads
        // the same way — scoping those would move feedback nobody asked to move.
        let h = makeHarness()
        let hud = SystemHUD(kind: .volume, value: 0.5)

        h.base.hudSource.emit(hud)

        #expect(await eventually {
            h.recorder.panel(for: Self.internalID)?.appliedFrames.last
                == Self.frame(.hud(hud), on: Self.internalScreen())
        })
        #expect(h.recorder.panel(for: Self.externalID)?.appliedFrames.last
            == Self.frame(.hud(hud), on: Self.externalScreen()))
        // Drawn on both, not merely touchable on both.
        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == true)
    }

    @Test func aHUDNamingADisplayIsNotDrawnOnTheOthers() async {
        // The frame alone cannot express this: the window is fixed and never
        // orders out, so a panel given the empty rect still RENDERS its content —
        // the bar would appear on both screens and only one would answer the
        // mouse. Content-level suppression is the channel that matters.
        let h = makeHarness()
        let hud = SystemHUD(
            kind: .screenBrightness, value: 0.4, display: Self.externalID, authority: .betterDisplay
        )

        h.base.hudSource.emit(hud)
        // Waited on the state, not on the flag: `showsHUD` starts true, so a
        // wait on it would be satisfied by the frame pass BEFORE the HUD lands.
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == false)
        // And the geometry agrees, so nothing on the quiet panel is touchable.
        #expect(h.recorder.panel(for: Self.internalID)?.appliedFrames.last
            == Self.frame(.hidden, on: Self.internalScreen()))
    }

    @Test func aHUDForADisplayThatIsGoneIsDrawnNowhere() async {
        // Unplugged between the report and the frame pass: no panel claims it.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, display: DisplayUUID(rawValue: "UNPLUGGED"))

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == false)
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == false)
    }

    @Test func theSlitStaysClickThroughWhileAHUDBelongsElsewhere() async {
        // A panel hidden only because the HUD is another display's must NOT arm
        // its click-invoke zone: the click it captured would die against
        // `invoke()`'s hidden-only guard instead of reaching the menu bar.
        let h = WindowManagerTests.Harness()
        let notched = ScreenDescription(
            id: Self.internalID,
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeTop: 32, auxLeft: 663.5, auxRight: 663.5
            ),
            isInternal: true
        )
        h.manager.updateScreens([notched, Self.externalScreen()])
        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.base.coordinator.mediaActive })

        h.base.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.4, display: Self.externalID))

        #expect(await eventually { h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == false })
        #expect(h.recorder.panel(for: Self.internalID)?.invokeZones.last == CGRect?.none)
    }

    @Test func hoverNeverArmsOnADisplayTheHUDIsNotOn() async {
        // Arming follows what is visible HERE; a panel showing nothing must not
        // react to the pointer, or an empty region would swallow clicks.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, display: Self.externalID)

        h.base.hudSource.emit(hud)

        #expect(await eventually { h.recorder.panel(for: Self.externalID)?.hoverArmedStates.last == true })
        #expect(h.recorder.panel(for: Self.internalID)?.hoverArmedStates.last == false)
    }

    @Test func theAppStateItselfStaysWhole() async {
        // Scoping is presentation only: the Coordinator still holds one HUD, so
        // a drag on the panel showing it acts on the display the HUD names.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, display: Self.externalID)

        h.base.hudSource.emit(hud)

        #expect(await eventually { h.base.coordinator.state == .hud(hud) })
    }
}
