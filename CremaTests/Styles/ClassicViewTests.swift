import Testing
@testable import Crema

/// ClassicView: content is a function of coordinator state; intents go
/// back through Coordinator methods. Same contract as the other skins.
@MainActor
struct ClassicViewTests {

    @Test func contentIsAFunctionOfPresentationState() async {
        let h = CoordinatorHarness()
        let view = ClassicView(coordinator: h.coordinator)
        #expect(view.contentKind == .empty)

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { view.contentKind == .nowPlayingCompact(track) })

        h.coordinator.hover(true)
        #expect(view.contentKind == .nowPlayingExpanded(track))

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)
        #expect(await eventually { view.contentKind == .hud(hud) })
    }

    @Test func scrubberReadsPositionFromNowPlayingNotFromState() async {
        let h = CoordinatorHarness()
        let view = ClassicView(coordinator: h.coordinator)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { view.scrubberPosition == 10 })

        let stateBefore = h.coordinator.state
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { view.scrubberPosition == 11 })
        #expect(h.coordinator.state == stateBefore)
    }

    @Test func intentsReachTheActuators() async {
        let h = CoordinatorHarness()
        let view = ClassicView(coordinator: h.coordinator)

        view.playPauseTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause] })

        view.previousTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack] })

        view.nextTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack, .nextTrack] })

        view.scrubbed(to: 42)
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack, .nextTrack, .seek(seconds: 42)] })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        _ = await eventually { view.contentKind == .hud(SystemHUD(kind: .volume, value: 0.5)) }
        view.hudSliderMoved(to: 0.7)
        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
    }

    @Test func displayPolicySuppressesNowPlaying() async {
        let h = CoordinatorHarness()
        let policy = SurfaceDisplayPolicy()
        policy.showsNowPlaying = false
        let view = ClassicView(coordinator: h.coordinator, displayPolicy: policy)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.coordinator.state != .hidden }

        #expect(view.contentKind == .empty)
    }
}
