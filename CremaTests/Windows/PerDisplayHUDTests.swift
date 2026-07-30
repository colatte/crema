import CoreGraphics
import Testing
@testable import Crema

/// Which display shows a HUD. The app has one state and one panel per screen, so
/// this is where a bar for a particular display stops being a bar on every
/// display — and stops being a control for a screen the user is not looking at.
///
/// The HUD does not name a UUID, it names a ROLE — no screen owns it, the
/// built-in panel, or a display it names — and this layer is the only one holding
/// the panel roster the role resolves against, so all three answers are pinned
/// here. Including the built-in one's asymmetry: a NAMED display the roster has
/// lost draws nowhere, while the built-in ROLE with no internal panel falls OPEN
/// to every display, because that case is reachable with the key already
/// swallowed and a consumed key owes feedback
/// (docs/DECISIONS.md: hud-target-is-a-role, hud-belongs-to-its-display).
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

    @Test func aHUDOwnedByNoDisplayShowsEverywhere() async {
        // Volume belongs to the output device and no screen owns it, so its bar
        // belongs on every panel — scoping it would move feedback nobody asked to
        // move. The built-in brightness used to read the same way and no longer
        // does: it names the internal panel as a ROLE, and the two facts stopped
        // sharing one spelling (docs/DECISIONS.md: hud-target-is-a-role).
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
            kind: .screenBrightness, value: 0.4, target: .display(Self.externalID), authority: .betterDisplay
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
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .display(DisplayUUID(rawValue: "UNPLUGGED")))

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

        h.base.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.4, target: .display(Self.externalID)))

        #expect(await eventually { h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == false })
        #expect(h.recorder.panel(for: Self.internalID)?.invokeZones.last == CGRect?.none)
    }

    @Test func hoverNeverArmsOnADisplayTheHUDIsNotOn() async {
        // Arming follows what is visible HERE; a panel showing nothing must not
        // react to the pointer, or an empty region would swallow clicks.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .display(Self.externalID))

        h.base.hudSource.emit(hud)

        #expect(await eventually { h.recorder.panel(for: Self.externalID)?.hoverArmedStates.last == true })
        #expect(h.recorder.panel(for: Self.internalID)?.hoverArmedStates.last == false)
    }

    @Test func theAppStateItselfStaysWhole() async {
        // Scoping is presentation only: the Coordinator still holds one HUD, so
        // a drag on the panel showing it acts on the display the HUD names.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .display(Self.externalID))

        h.base.hudSource.emit(hud)

        #expect(await eventually { h.base.coordinator.state == .hud(hud) })
    }

    @Test func builtInBrightnessIsDrawnOnlyOnTheBuiltInPanel() async {
        // The local brightness border reads and writes the built-in panel and no
        // other, and since `brightness-key-follows-the-pointer` the key is only
        // swallowed with the pointer there — so this bar describes the internal
        // screen and nothing else. Drawn on the monitor it is a live CONTROL for a
        // display the user is not looking at: every panel is handed `.hud`, and a
        // drag on the monitor's copy would dim the laptop in silence. Asserted with
        // the same quartet the named-display path uses, because a half scope
        // (content without hover, frame without content) is its own bug.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .builtIn)

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == false)
        #expect(h.recorder.panel(for: Self.externalID)?.appliedFrames.last
            == Self.frame(.hidden, on: Self.externalScreen()))
        #expect(h.recorder.panel(for: Self.externalID)?.hoverArmedStates.last == false)
        #expect(h.recorder.panel(for: Self.externalID)?.invokeZones.last == CGRect?.none)
    }

    @Test func theKeyboardBacklightBarStaysOnEveryDisplay() async {
        // The backlight belongs to the one keyboard, not to a screen, and its
        // actuator takes no display at all — so scoping it would hide feedback and
        // buy no aim. It shares a source type and an emit line with the screen
        // channel, which is exactly why it needs a guard of its own.
        let h = makeHarness()
        let hud = SystemHUD(kind: .keyboardBrightness, value: 0.4)

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == true)
    }

    @Test func builtInBrightnessShowsEverywhereWhenNoPanelIsTheBuiltIn() async {
        // The fall-open, and why it is not an oversight: the roster can genuinely
        // carry no internal panel while the key was still swallowed — AppKit
        // collapses a mirror set to one NSScreen that may not be the internal one,
        // and a screen with no NSScreenNumber is dropped. A consumed key owes
        // feedback, so the bar goes back to every display rather than to none.
        // Narrow on purpose: a display that was NAMED and is gone still shows
        // nowhere, which the unplug case above pins.
        let h = WindowManagerTests.Harness()
        let secondID = DisplayUUID(rawValue: "EXTERNAL-2")
        let second = ScreenDescription(
            id: secondID,
            geometry: ScreenGeometry(frame: CGRect(x: 5000, y: 0, width: 2560, height: 1440)),
            isInternal: false
        )
        h.manager.updateScreens([Self.externalScreen(), second])
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .builtIn)

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: secondID)?.showsHUDStates.last == true)
    }

    @Test func aDragOnTheBuiltInBarKeepsTheBarOnTheBuiltInPanel() async {
        // The scoping is only as good as what the DRAG republishes. The slider has no
        // local value, so `hudSliderChanged` publishes `hud.at(value)` synchronously
        // before the write leaves, and THAT republished HUD is what every panel is
        // scoped against. A copy that dropped the target would hand the monitor a live
        // control for the laptop for the rest of the gesture and its linger — the
        // reported bug with one extra step, and now already under the finger
        // (docs/DECISIONS.md: hud-target-is-a-role).
        //
        // Asserted against a literal HUD, never `hud.at(0.9)`: an expectation built
        // with the very call under test agrees with any mutation of it.
        let h = makeHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4, target: .builtIn)

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        h.base.coordinator.hudSliderChanged(to: 0.9)

        #expect(h.base.coordinator.state
            == .hud(SystemHUD(kind: .screenBrightness, value: 0.9, target: .builtIn)))
        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == false)
    }

    @Test func aDragOnANamedDisplaysBarKeepsTheBarOnThatDisplay() async {
        // The same claim on the other path, and not a copy of it: the neighbour's
        // confirming echo re-publishes the applied HUD VERBATIM
        // (`BetterDisplayOSDSource.noteApplied`) instead of re-sampling a source, so a
        // target lost in the copy reaches presentation here by a different route —
        // the monitor's bar spreading onto the laptop mid-drag.
        let h = makeHarness()
        let hud = SystemHUD(
            kind: .screenBrightness, value: 0.4, target: .display(Self.externalID), authority: .betterDisplay
        )

        h.base.hudSource.emit(hud)
        #expect(await eventually { h.base.coordinator.state == .hud(hud) })

        h.base.coordinator.hudSliderChanged(to: 0.9)

        #expect(h.base.coordinator.state == .hud(SystemHUD(
            kind: .screenBrightness, value: 0.9, target: .display(Self.externalID), authority: .betterDisplay
        )))
        #expect(h.recorder.panel(for: Self.externalID)?.showsHUDStates.last == true)
        #expect(h.recorder.panel(for: Self.internalID)?.showsHUDStates.last == false)
    }
}
