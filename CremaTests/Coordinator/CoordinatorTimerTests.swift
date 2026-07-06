import Testing
@testable import Crema

/// HUD revert timers driven by an injectable clock; tests never sleep.
@MainActor
struct CoordinatorTimerTests {

    @Test func hudRevertsToNowPlayingAfterDelay() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        await h.clock.waitForSleep()
        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func hudRevertsToHiddenWithoutMedia() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.2))
        #expect(await eventually { h.coordinator.state != .hidden })

        await h.clock.waitForSleep()
        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func newHUDEventRestartsTheTimer() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.3))
        await h.clock.waitForSleep()

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.4))

        // The first timer must be cancelled and a fresh one parked.
        #expect(await eventually { h.clock.cancelledCount == 1 })
        await h.clock.waitForSleep()
        #expect(h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.4)))

        h.clock.advance()
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func usesTheDefaultDelayFromASinglePlace() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        await h.clock.waitForSleep()

        #expect(Coordinator.defaultHUDRevertDelay == 1.5)
        #expect(h.clock.delays == [Coordinator.defaultHUDRevertDelay])
    }

    @Test func delayIsConfigurable() async {
        let h = CoordinatorHarness(hudRevertDelay: 0.25)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        await h.clock.waitForSleep()

        #expect(h.clock.delays == [0.25])
    }

    @Test func revertRestoresExpandedNowPlayingWhenHovering() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.hover(true)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        await h.clock.waitForSleep()
        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: true) })
    }
}
