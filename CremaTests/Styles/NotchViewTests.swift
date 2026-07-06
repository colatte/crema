import Testing
@testable import Crema

/// NotchView: content is a function of coordinator state; intents go back
/// through Coordinator methods; scrubber position comes from `nowPlaying`. Same
/// contract CardViewTests holds for the card.
@MainActor
struct NotchViewTests {

    @Test func contentIsAFunctionOfPresentationState() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)
        #expect(view.contentKind == .empty)

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { view.contentKind == .nowPlayingCompact(track) })

        // Drive expansion directly (the timed intent path is tested separately).
        h.coordinator.hover(true)
        #expect(view.contentKind == .nowPlayingExpanded(track))

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)
        #expect(await eventually { view.contentKind == .hud(hud) })
    }

    @Test func scrubberReadsPositionFromNowPlayingNotFromState() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { view.scrubberPosition == 10 })

        let stateBefore = h.coordinator.state
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { view.scrubberPosition == 11 })
        #expect(h.coordinator.state == stateBefore)
    }

    @Test func playPauseIntentReachesTheMediaActuator() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)

        view.playPauseTapped()

        #expect(await eventually { h.media.commands == [.togglePlayPause] })
    }

    @Test func scrubIntentReachesTheMediaActuator() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)

        view.scrubbed(to: 42)

        #expect(await eventually { h.media.commands == [.seek(seconds: 42)] })
    }

    @Test func hudSliderIntentRoutesToTheRightActuator() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { view.contentKind == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        view.hudSliderMoved(to: 0.7)

        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
        #expect(h.screen.commands.isEmpty)
        #expect(h.keyboard.commands.isEmpty)
    }

    @Test func skipIntentsReachTheMediaActuator() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)

        view.previousTapped()
        #expect(await eventually { h.media.commands == [.previousTrack] })

        view.nextTapped()
        #expect(await eventually { h.media.commands == [.previousTrack, .nextTrack] })
    }

    @Test func controlsDisableWhenCommandsAreUnavailable() async {
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)
        #expect(view.controlsEnabled)

        h.media.shouldThrow = true
        view.playPauseTapped()

        #expect(await eventually { !view.controlsEnabled })
    }

    @Test func skipsDisableIndependentlyOfPlayPause() async {
        // The buttons bind to the view's passthrough — pin it, not just the
        // Coordinator property, so rewiring skipEnabled to the general flag
        // couldn't go green.
        let h = CoordinatorHarness()
        let view = NotchView(coordinator: h.coordinator)
        #expect(view.skipControlsEnabled)

        h.media.shouldThrow = true
        view.nextTapped()

        #expect(await eventually { !view.skipControlsEnabled })
        #expect(view.controlsEnabled)
    }
}
