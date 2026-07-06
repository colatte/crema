import Testing
@testable import Crema

/// The Settings now-playing behavior toggles, applied live to the
/// Coordinator: quiet vs reactive appearance, and the browser-media switch.
@MainActor
struct CoordinatorNowPlayingModeTests {

    @Test func reactiveModeSurfacesOnAMediaEvent() async {
        let h = CoordinatorHarness(reactiveNowPlaying: true)
        let track = CoordinatorHarness.playingTrack()

        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func quietModeDoesNotSurfaceButStillTracksTheMedia() async {
        // Quiet: no self-appearance, yet nowPlaying/mediaActive are tracked so
        // click-invoke still works and the compact can be summoned.
        let h = CoordinatorHarness(reactiveNowPlaying: false)
        let track = CoordinatorHarness.playingTrack()

        h.nowPlayingSource.emit(track)
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == track)
        #expect(h.coordinator.mediaActive)
    }

    @Test func quietModeStillOpensOnAClickInvoke() async {
        let h = CoordinatorHarness(reactiveNowPlaying: false)
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        await settle()
        #expect(h.coordinator.state == .hidden)

        h.coordinator.invoke()

        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
    }

    @Test func switchingToReactiveAppliesToTheNextEvent() async {
        let h = CoordinatorHarness(reactiveNowPlaying: false)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "A"))
        await settle()
        #expect(h.coordinator.state == .hidden)

        h.coordinator.setReactiveNowPlaying(true)
        let next = CoordinatorHarness.playingTrack(title: "B")
        h.nowPlayingSource.emit(next)

        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })
    }

    @Test func switchingToQuietStopsFutureSelfAppearances() async {
        let h = CoordinatorHarness(reactiveNowPlaying: true)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "A"))
        #expect(await eventually { h.coordinator.state != .hidden })

        // Let the linger tuck it away, then go quiet: a fresh track must not
        // pop back up on its own.
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        h.coordinator.setReactiveNowPlaying(false)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "B"))
        await settle()
        #expect(h.coordinator.state == .hidden)
    }

    @Test func quietModeRecoversBlockedControlsOnANewEvent() async {
        // Degraded controls must re-check optimism on a fresh media event even
        // in quiet mode — the surface still gets invoked/hovered, so the
        // recovery can't depend on the self-surfacing that quiet suppresses.
        let h = CoordinatorHarness(reactiveNowPlaying: false)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "A"))
        await settle()
        #expect(h.coordinator.state == .hidden)

        h.media.shouldThrow = true
        h.coordinator.togglePlayPause()
        #expect(await eventually { !h.coordinator.commandsAvailable })

        h.media.shouldThrow = false
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "B"))
        #expect(await eventually { h.coordinator.commandsAvailable })
        #expect(h.coordinator.state == .hidden)   // still quiet, no surface
    }

    @Test func includingBrowsersLetsAVisibleBrowserThrough() async {
        let h = CoordinatorHarness(ignoresBrowserMedia: false)
        let video = NowPlaying(title: "Web", isPlaying: true, position: 0, sourceBundleID: "com.apple.Safari")

        h.nowPlayingSource.emit(video)

        #expect(await eventually { h.coordinator.state == .nowPlaying(video, expanded: false) })
    }

    @Test func turningOnIgnoreDropsAVisibleBrowserAppearance() async {
        // Include first (browser visible), then flip ignore on live: the
        // browser snapshot must be discarded, not left lingering.
        let h = CoordinatorHarness(ignoresBrowserMedia: false)
        let video = NowPlaying(title: "Web", isPlaying: true, position: 0, sourceBundleID: "com.apple.Safari")
        h.nowPlayingSource.emit(video)
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.setIgnoresBrowserMedia(true)

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func turningOnIgnoreLeavesARealPlayerAlone() async {
        let h = CoordinatorHarness(ignoresBrowserMedia: false)
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.coordinator.setIgnoresBrowserMedia(true)

        // A non-browser appearance is untouched by the browser switch.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        #expect(h.coordinator.nowPlaying == track)
    }
}
