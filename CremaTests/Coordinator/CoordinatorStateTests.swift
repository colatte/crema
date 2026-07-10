import Observation
import Testing
@testable import Crema

/// State machine and HUD priority, all with mocked sources.
@MainActor
struct CoordinatorStateTests {

    @Test func startsHidden() {
        let h = CoordinatorHarness()
        #expect(h.coordinator.state == .hidden)
    }

    @Test func playingMediaShowsNowPlayingCompact() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()

        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func pausedMediaShowsAPausedAppearanceThenTucks() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.coordinator.state != .hidden })

        // Pause is a media event: a compact appearance reflecting the paused
        // state, tucked away by the linger timer.
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) })

        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aFirstPausedEventDoesNotSelfSurface() async {
        // Contract: a paused app appearing from nothing (previous == nil) is
        // not news — nothing started playing — so it must not pop on its own,
        // though it is still tracked for click-invoke/hover.
        let h = CoordinatorHarness()
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)

        h.nowPlayingSource.emit(paused)
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == paused)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func switchingToADifferentPlayingAppSurfaces() async {
        // A different source that lands PLAYING is news: it pops.
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Breathe"))
        #expect(await eventually { h.coordinator.state != .hidden })

        let other = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(other)

        #expect(await eventually { h.coordinator.state == .nowPlaying(other, expanded: false) })
    }

    @Test func aPausedTrackChangeDoesNotSelfSurface() async {
        // Contract: a paused app skipping tracks (previous non-nil, both paused,
        // same source) changed identity but nothing started playing — the switch
        // is not news, so it must not pop, though the snapshot follows to B.
        let h = CoordinatorHarness()

        // Establish a paused track A with the surface already tucked to hidden.
        let playingA = CoordinatorHarness.playingTrack(title: "Breathe")
        h.nowPlayingSource.emit(playingA)
        #expect(await eventually { h.coordinator.state == .nowPlaying(playingA, expanded: false) })
        let pausedA = CoordinatorHarness.playingTrack(title: "Breathe", isPlaying: false)
        h.nowPlayingSource.emit(pausedA)
        #expect(await eventually { h.coordinator.state == .nowPlaying(pausedA, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        // Skip to a different paused track from the same source.
        let pausedB = CoordinatorHarness.playingTrack(title: "Time", isPlaying: false)
        h.nowPlayingSource.emit(pausedB)
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == pausedB)
    }

    @Test func aDifferentAppArrivingPausedDoesNotSelfSurface() async {
        // Contrast with switchingToADifferentPlayingAppSurfaces: a different app
        // taking over while paused (previous non-nil) lands with nothing playing,
        // so it must not pop — only a different app that arrives playing is news.
        let h = CoordinatorHarness()

        // App A plays, surfaces, and tucks away.
        let playingA = CoordinatorHarness.playingTrack(title: "Breathe")
        h.nowPlayingSource.emit(playingA)
        #expect(await eventually { h.coordinator.state == .nowPlaying(playingA, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        // A different app arrives already paused.
        let pausedB = CoordinatorHarness.playingTrack(title: "Time", isPlaying: false)
        h.nowPlayingSource.emit(pausedB)
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == pausedB)
    }

    @Test func hudInterruptsNowPlaying() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.coordinator.state != .hidden })

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)

        #expect(await eventually { h.coordinator.state == .hud(hud) })
    }

    @Test func mediaUpdateDoesNotPreemptHUD() async {
        let h = CoordinatorHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 0.4)
        h.hudSource.emit(hud)
        #expect(await eventually { h.coordinator.state == .hud(hud) })

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.nowPlaying == track })
        #expect(h.coordinator.state == .hud(hud))
    }

    @Test func positionTickUpdatesNowPlayingButNotState() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 10 })

        let stateChanged = Flag()
        withObservationTracking {
            _ = h.coordinator.state
        } onChange: {
            stateChanged.value = true
        }

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))

        #expect(await eventually { h.coordinator.nowPlaying?.position == 11 })
        await settle()
        #expect(!stateChanged.value)
    }

    @Test func presentationHookFiresSynchronouslyWithTheWrite() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        // The WindowManager resizes windows from this hook; it must run inside
        // the write's callout (no awaits below) or the render beats the resize.
        let fired = Flag()
        h.coordinator.onPresentationChange = { fired.value = true }

        h.coordinator.hover(true)

        #expect(fired.value)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
    }

    @Test func contentChangeDoesRewriteState() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "One"))
        #expect(await eventually { h.coordinator.nowPlaying?.title == "One" })

        let stateChanged = Flag()
        withObservationTracking {
            _ = h.coordinator.state
        } onChange: {
            stateChanged.value = true
        }

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Two", position: 99))

        #expect(await eventually { stateChanged.value })
        #expect(await eventually {
            h.coordinator.state == .nowPlaying(CoordinatorHarness.playingTrack(title: "Two", position: 99), expanded: false)
        })
    }
}
