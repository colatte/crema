// One suite per window-management concern would splinter the panel harness;
// the file grew past the ceiling with the P5 pinning fence — large by accretion.
// swiftlint:disable file_length
import CoreGraphics
import Foundation
import Testing
@testable import Crema

// Test fixtures force-unwrap known values (a nil means the test itself is broken).
// swiftlint:disable force_unwrapping

/// WindowManager logic over fake screens and panels: screen
/// reconciliation, state-driven frames, per-display style resolution.
@MainActor
struct WindowManagerTests {

    @MainActor
    final class Harness {
        let base = CoordinatorHarness()
        private let store = EphemeralDefaults()
        let preferences: Preferences
        let recorder = PanelRecorder()
        let manager: WindowManager

        init() {
            preferences = Preferences(defaults: store.defaults)
            manager = WindowManager(
                coordinator: base.coordinator,
                preferences: preferences
            ) { [recorder] screen, style, _ in
                recorder.make(screen, style)
            }
            manager.start()
        }
    }

    private static func screen(
        _ uuid: String,
        isInternal: Bool = true,
        frame: CGRect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    ) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            geometry: ScreenGeometry(frame: frame),
            isInternal: isInternal
        )
    }

    /// A display that reports a real notch (non-zero safeTop + aux areas).
    private static func notchedScreen(_ uuid: String) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                safeTop: 32,
                auxLeft: 663.5,
                auxRight: 663.5
            ),
            isInternal: true
        )
    }

    // MARK: - reconciliation

    @Test func connectingScreensCreatesOnePanelPerScreen() {
        let h = Harness()
        h.manager.updateScreens([Self.screen("A"), Self.screen("B", isInternal: false, frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))])

        #expect(h.recorder.created.count == 2)
        #expect(Set(h.recorder.created.map(\.screen.id.rawValue)) == ["A", "B"])
    }

    @Test func disconnectingAScreenClosesItsPanelOnly() {
        let h = Harness()
        let a = Self.screen("A")
        let b = Self.screen("B", isInternal: false)
        h.manager.updateScreens([a, b])

        h.manager.updateScreens([a])

        #expect(h.recorder.panel(for: b.id)?.closed == true)
        #expect(h.recorder.panel(for: a.id)?.closed == false)
        #expect(h.recorder.created.count == 2)
    }

    @Test func unchangedScreensKeepTheirPanel() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])
        h.manager.updateScreens([a])

        #expect(h.recorder.created.count == 1)
    }

    // MARK: - frame follows state via the active style rule

    @Test func stateChangeAppliesTheActiveStyleRuleFrame() async {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])

        let track = CoordinatorHarness.playingTrack()
        h.base.nowPlayingSource.emit(track)

        let expected = Style.card.frame(for: .nowPlaying(track, expanded: false), on: a.geometry)
        #expect(await eventually { h.recorder.panel(for: a.id)?.appliedFrames.last == expected })
    }

    @Test func initialFrameIsTheHiddenRuleFrame() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])

        #expect(h.recorder.panel(for: a.id)?.appliedFrames == [Style.card.frame(for: .hidden, on: a.geometry)])
    }

    @Test func positionTickDoesNotReapplyFrames() async {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])
        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { h.base.coordinator.nowPlaying?.position == 10 })
        await settle()
        let applied = h.recorder.panel(for: a.id)!.appliedFrames.count

        // The manager observes `state`, never `nowPlaying`: the tick is silent.
        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { h.base.coordinator.nowPlaying?.position == 11 })
        await settle()

        #expect(h.recorder.panel(for: a.id)!.appliedFrames.count == applied)
    }

    // MARK: - per-display style resolution via Preferences

    @Test func panelCreationConsultsThePreferredStyle() {
        let h = Harness()
        let a = Self.screen("A")
        h.preferences.setStyle(.card, for: a.id)

        h.manager.updateScreens([a])

        #expect(h.recorder.created.first?.style == .card)
        #expect(h.recorder.panel(for: a.id)?.appliedFrames.last == Style.card.frame(for: .hidden, on: a.geometry))
    }

    @Test func refreshStylesSwapsThePanelWhenThePreferenceChanges() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])
        let firstPanel = h.recorder.panel(for: a.id)

        h.preferences.setStyle(.classic, for: a.id)
        h.manager.refreshStyles()

        #expect(firstPanel?.closed == true)
        #expect(h.recorder.created.count == 2)
        #expect(h.recorder.created.last?.style == .classic)
    }

    @Test func notchPreferenceStaysNotchOnADisplayWithANotch() {
        let h = Harness()
        let n = Self.notchedScreen("N")
        h.preferences.setStyle(.notch, for: n.id)

        h.manager.updateScreens([n])

        #expect(h.recorder.created.first?.style == .notch)
        #expect(h.recorder.panel(for: n.id)?.appliedFrames.last == Style.notch.frame(for: .hidden, on: n.geometry))
    }

    @Test func notchPreferenceResolvesToCardOnADisplayWithoutANotch() {
        let h = Harness()
        let a = Self.screen("A")   // safeTop == 0: no physical notch
        h.preferences.setStyle(.notch, for: a.id)

        h.manager.updateScreens([a])

        // Orphan notch preference degrades to the card (graceful path).
        #expect(h.recorder.created.first?.style == .card)
        #expect(h.recorder.panel(for: a.id)?.appliedFrames.last == Style.card.frame(for: .hidden, on: a.geometry))
    }

    @Test func refreshStylesResolvesNotchToCardOnANonNotchDisplay() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])   // starts as the default notch, resolved to card (no slit)

        h.preferences.setStyle(.notch, for: a.id)
        h.manager.refreshStyles()

        // Resolution matches the initial card → no spurious panel swap.
        #expect(h.recorder.created.count == 1)
        #expect(h.recorder.panel(for: a.id)?.closed == false)
    }

    @Test func safeTopChangeOnAKeptDisplayRebuildsThePanel() {
        let h = Harness()
        let notched = Self.notchedScreen("N")   // safeTop 32
        h.preferences.setStyle(.notch, for: notched.id)
        h.manager.updateScreens([notched])
        let firstPanel = h.recorder.panel(for: notched.id)
        #expect(h.recorder.created.count == 1)

        // Same display (same UUID), new scale mode → different safeTop. The
        // panel captured the old slit inset, so it must be rebuilt.
        let rescaled = ScreenDescription(
            id: notched.id,
            geometry: ScreenGeometry(frame: notched.geometry.frame, safeTop: 38, auxLeft: 620, auxRight: 620),
            isInternal: true
        )
        h.manager.updateScreens([rescaled])

        #expect(firstPanel?.closed == true)
        #expect(h.recorder.created.count == 2)
    }

    @Test func aFrameMoveOnAKeptDisplayRebuildsThePanel() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])
        let firstPanel = h.recorder.panel(for: a.id)

        // Same UUID, only the frame origin moved (display rearranged): the
        // panel's captured hover regions are screen-space rects, so keeping it
        // would leave hover detecting at the old position — rebuild.
        let moved = Self.screen("A", frame: CGRect(x: 500, y: 0, width: 1000, height: 600))
        h.manager.updateScreens([moved])

        #expect(firstPanel?.closed == true)
        #expect(h.recorder.created.count == 2)
    }

    @Test func refreshStylesWithoutChangesKeepsPanels() {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])

        h.manager.refreshStyles()

        #expect(h.recorder.created.count == 1)
        #expect(h.recorder.panel(for: a.id)?.closed == false)
    }

    /// Panel double that commits a hover from inside its first armed apply —
    /// exactly what arming a real hover monitor does when the cursor is already
    /// inside the region (setActive → sample → report → hover).
    @MainActor
    private final class HoverCommittingPanel: PresentationPanel {
        private(set) var appliedFrames: [CGRect] = []
        var onFirstArmedApply: (() -> Void)?

        // swiftlint:disable:next function_parameter_count
        func apply(
            frame: CGRect,
            hoverArmed: Bool,
            showsNowPlaying: Bool,
            showsControls: Bool,
            hudIndicatorStyle: HUDIndicatorStyle,
            invokeZone: CGRect?
        ) {
            appliedFrames.append(frame)
            if hoverArmed, let fire = onFirstArmedApply {
                onFirstArmedApply = nil
                fire()
            }
        }

        func close() {}
    }

    @Test func aNestedHoverCommitDuringAFramePassConvergesOnTheFreshState() async {
        // Every frame pass must go through the re-entrancy guard: a nested
        // state write (here, the hover committed mid-apply) defers, and the
        // final pass runs with the final state — two passes never interleave,
        // and no panel is left holding a stale pre-write frame.
        let base = CoordinatorHarness()
        let store = EphemeralDefaults()
        let preferences = Preferences(defaults: store.defaults)
        let panel = HoverCommittingPanel()
        let manager = WindowManager(coordinator: base.coordinator, preferences: preferences) { _, _, _ in panel }
        manager.start()

        let track = CoordinatorHarness.playingTrack()
        base.nowPlayingSource.emit(track)
        _ = await eventually { base.coordinator.state == .nowPlaying(track, expanded: false) }

        panel.onFirstArmedApply = { [coordinator = base.coordinator] in
            coordinator.hover(true)
        }
        // updateScreens is one of the passes that used to bypass the guard.
        manager.updateScreens([Self.screen("A")])

        #expect(base.coordinator.state == .nowPlaying(track, expanded: true))
        let geometry = Self.screen("A").geometry
        #expect(panel.appliedFrames.last == Style.card.frame(for: .nowPlaying(track, expanded: true), on: geometry))
    }

    @Test func stateChangeAppliesFramesInTheSameCallout() async {
        let h = Harness()
        let a = Self.screen("A")
        h.manager.updateScreens([a])
        let track = CoordinatorHarness.playingTrack()
        h.base.nowPlayingSource.emit(track)
        _ = await eventually { h.base.coordinator.state == .nowPlaying(track, expanded: false) }
        let before = h.recorder.panel(for: a.id)!.appliedFrames.count

        // The panels' event routing (click-interactive region, hover arming)
        // must track the state in the same callout as the write — an async hop
        // would leave a beat where the visible surface and the routed region
        // disagree. No awaits between the intent and the assertions.
        h.base.coordinator.hover(true)

        let applied = h.recorder.panel(for: a.id)!.appliedFrames
        #expect(applied.count > before)
        #expect(applied.last == Style.card.frame(for: .nowPlaying(track, expanded: true), on: a.geometry))
    }

    @Test func hoverArmsOnlyWhileVisibleAndTuckingHandsOffToTheInvokeZone() async {
        let h = Harness()
        // A notched internal display: the notch style is the one with a
        // click-invoke zone (the physical slit).
        let internalScreen = Self.notchedScreen("N")
        let externalScreen = Self.screen("B", isInternal: false, frame: CGRect(x: 2000, y: 0, width: 1200, height: 800))
        h.manager.updateScreens([internalScreen, externalScreen])

        // No media, nothing visible: disarmed everywhere, no invoke zone.
        #expect(h.recorder.panel(for: internalScreen.id)?.hoverArmedStates.last == false)
        #expect(h.recorder.panel(for: internalScreen.id)?.invokeZones.last == CGRect?.none)

        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.base.coordinator.state != .hidden }

        // Visible appearance: hover arms on the internal display (now-playing
        // on); no invoke zone while something is on screen. The external
        // display ("show now playing here" off) never arms.
        #expect(await eventually { h.recorder.panel(for: internalScreen.id)?.hoverArmedStates.last == true })
        #expect(h.recorder.panel(for: internalScreen.id)?.invokeZones.last == CGRect?.none)
        #expect(h.recorder.panel(for: externalScreen.id)?.hoverArmedStates.last == false)

        // Tucked with media playing: hover disarms (an empty region never
        // reacts to the pointer — the accidental-appearance fix) and the
        // click-invoke zone takes over: the notch's slit rect.
        await h.base.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.base.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.base.coordinator.state == .hidden }
        #expect(await eventually { h.recorder.panel(for: internalScreen.id)?.hoverArmedStates.last == false })
        #expect(
            h.recorder.panel(for: internalScreen.id)?.invokeZones.last
                == NotchStyle().invokeZone(on: internalScreen.geometry)
        )
        // The suppressed display gets no invoke zone either.
        #expect(h.recorder.panel(for: externalScreen.id)?.invokeZones.last == CGRect?.none)
    }

    @Test func floatingStylesGetNoInvokeZoneEvenWhenTuckedAndPlaying() async {
        // The card's region sits over live app content — capturing clicks
        // there would steal toolbar/desktop interactions, so only the notch
        // (dead slit) click-invokes.
        let h = Harness()
        let a = Self.screen("A", isInternal: true)   // no slit ⇒ resolves to card
        h.manager.updateScreens([a])

        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.base.coordinator.state != .hidden }
        await h.base.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.base.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.base.coordinator.state == .hidden }

        #expect(h.base.coordinator.mediaActive)
        #expect(h.recorder.panel(for: a.id)?.invokeZones.last == CGRect?.none)
    }

    @Test func aPausedAppearanceKeepsHoverArmedUntilItTucks() async {
        let h = Harness()
        let a = Self.screen("A", isInternal: true)
        h.manager.updateScreens([a])
        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.base.coordinator.state != .hidden }

        // Paused: media inactive, but the appearance is on screen for its
        // linger — hover must still be able to hold it.
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.base.nowPlayingSource.emit(paused)
        #expect(await eventually { h.base.coordinator.state == .nowPlaying(paused, expanded: false) })
        #expect(h.recorder.panel(for: a.id)?.hoverArmedStates.last == true)

        // Tucked with media paused: disarmed, and no invoke zone either —
        // paused media is not click-invokable (same rule as the old
        // paused-resurface decision).
        await h.base.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.base.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.base.coordinator.state == .hidden })
        #expect(await eventually { h.recorder.panel(for: a.id)?.hoverArmedStates.last == false })
        #expect(h.recorder.panel(for: a.id)?.invokeZones.last == CGRect?.none)
    }

    @Test func showsNowPlayingPolicyReachesEachPanel() async {
        // The fixed window never orders out, so per-display suppression happens
        // in the view via this flag — the frame alone no longer hides anything.
        let h = Harness()
        let internalScreen = Self.screen("A", isInternal: true)
        let externalScreen = Self.screen("B", isInternal: false, frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))
        h.manager.updateScreens([internalScreen, externalScreen])

        h.base.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.base.coordinator.state != .hidden }

        #expect(await eventually { h.recorder.panel(for: internalScreen.id)?.showsNowPlayingStates.last == true })
        #expect(h.recorder.panel(for: externalScreen.id)?.showsNowPlayingStates.last == false)
    }

    @Test func nowPlayingIsHiddenOnDisplaysWithTheToggleOff() async {
        let h = Harness()
        let internalScreen = Self.screen("A", isInternal: true)
        let externalScreen = Self.screen("B", isInternal: false, frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))
        h.manager.updateScreens([internalScreen, externalScreen])

        let track = CoordinatorHarness.playingTrack()
        h.base.nowPlayingSource.emit(track)

        // Default policy: now playing only on the internal display; the
        // external panel gets the hidden frame. HUDs are unaffected.
        let state = PresentationState.nowPlaying(track, expanded: false)
        #expect(await eventually { h.recorder.panel(for: internalScreen.id)?.appliedFrames.last == Style.card.frame(for: state, on: internalScreen.geometry) })
        #expect(h.recorder.panel(for: externalScreen.id)?.appliedFrames.last == Style.card.frame(for: .hidden, on: externalScreen.geometry))

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.base.hudSource.emit(hud)
        #expect(await eventually { h.recorder.panel(for: externalScreen.id)?.appliedFrames.last == Style.card.frame(for: .hud(hud), on: externalScreen.geometry) })
    }

    // Provenance: the pinned-latent fence P5 from CONTRACTS-AUDIT — kept by
    // behavior, named by behavior.
    @Test func setShowsNowPlayingIsHonoredLiveBothDirections() async {
        // Pinned-latent fence: setShowsNowPlaying has no
        // Settings writer yet, but WindowManager honors the pref LIVE. This pins
        // the honored side by writing the pref DIRECTLY via Preferences (the
        // path a future toggle will take) and asserting both directions:
        // flipping it off suppresses the surface and disarms hover on a display
        // that would otherwise show it; flipping it on surfaces one that
        // wouldn't by default. If the reader is ever removed as "dead", this
        // fails — proving the behavior is reachable and must not be dropped.
        let h = Harness()
        let internalScreen = Self.screen("A", isInternal: true)   // defaults on
        let externalScreen = Self.screen("B", isInternal: false, frame: CGRect(x: 1000, y: 0, width: 1200, height: 800))   // defaults off

        // Invert both defaults through the writer under test.
        h.preferences.setShowsNowPlaying(false, on: internalScreen.id)
        h.preferences.setShowsNowPlaying(true, on: externalScreen.id)
        h.manager.updateScreens([internalScreen, externalScreen])

        let track = CoordinatorHarness.playingTrack()
        h.base.nowPlayingSource.emit(track)
        _ = await eventually { h.base.coordinator.state != .hidden }

        let state = PresentationState.nowPlaying(track, expanded: false)
        // Internal, now flipped OFF: surface suppressed to the hidden frame,
        // showsNowPlaying=false, and hover never arms (empty region).
        #expect(await eventually {
            h.recorder.panel(for: internalScreen.id)?.appliedFrames.last
                == Style.card.frame(for: .hidden, on: internalScreen.geometry)
        })
        #expect(h.recorder.panel(for: internalScreen.id)?.showsNowPlayingStates.last == false)
        #expect(h.recorder.panel(for: internalScreen.id)?.hoverArmedStates.last == false)

        // External, now flipped ON: surface shown at the now-playing frame,
        // showsNowPlaying=true, hover armed.
        #expect(await eventually {
            h.recorder.panel(for: externalScreen.id)?.appliedFrames.last
                == Style.card.frame(for: state, on: externalScreen.geometry)
        })
        #expect(h.recorder.panel(for: externalScreen.id)?.showsNowPlayingStates.last == true)
        #expect(h.recorder.panel(for: externalScreen.id)?.hoverArmedStates.last == true)
    }

    @Test func showControlsPreferenceReachesEachPanelAndReappliesLive() {
        // View-only is a global preference the panel carries into the view;
        // refreshPresentation re-applies it without recreating the panel.
        let h = Harness()
        let screen = Self.screen("A")
        h.preferences.showsPlaybackControls = false
        h.manager.updateScreens([screen])
        #expect(h.recorder.panel(for: screen.id)?.showsControlsStates.last == false)

        h.preferences.showsPlaybackControls = true
        h.manager.refreshPresentation()
        #expect(h.recorder.panel(for: screen.id)?.showsControlsStates.last == true)
    }

    @Test func hudIndicatorStylePreferenceReachesEachPanelAndReappliesLive() {
        // The HUD indicator appearance is a global preference the panel carries
        // into the view (render context, like show-controls); refreshPresentation
        // re-applies it without recreating the panel.
        let h = Harness()
        let screen = Self.screen("A")
        h.preferences.hudIndicatorStyle = .filled
        h.manager.updateScreens([screen])
        #expect(h.recorder.panel(for: screen.id)?.hudIndicatorStyleStates.last == .filled)

        h.preferences.hudIndicatorStyle = .slider
        h.manager.refreshPresentation()
        #expect(h.recorder.panel(for: screen.id)?.hudIndicatorStyleStates.last == .slider)
    }
}

// swiftlint:enable force_unwrapping
