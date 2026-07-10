import Testing
@testable import Crema

/// Browser media is treated as nothing playing (default policy): it must not
/// surface, and it must strip a stale snapshot so hover/click never arm for a
/// ghost. Injectable flag so the toggle can flip it.
@MainActor
struct CoordinatorBrowserFilterTests {

    private func browserTrack(title: String = "Autoplay Video") -> NowPlaying {
        NowPlaying(
            title: title,
            isPlaying: true,
            position: 0,
            sourceBundleID: "com.apple.Safari"
        )
    }

    @Test func browserMediaNeverSurfaces() async {
        let h = CoordinatorHarness()

        h.nowPlayingSource.emit(browserTrack())
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aBrowserTakingOverDropsTheVisibleAppearanceAndDisarms() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        // A feed video steals the system's now-playing focus: the real player
        // effectively stopped — surface, snapshot and arming must all drop.
        h.nowPlayingSource.emit(browserTrack())

        #expect(await eventually { h.coordinator.state == .hidden })
        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aRealPlayerAfterABrowserReearnsTheAppearance() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(browserTrack())
        await settle()

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        #expect(h.coordinator.mediaActive)
    }

    @Test func aBrowserTakeoverDuringAHUDLeavesNothingToResurface() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        // The feed video steals focus while the HUD owns the surface: the
        // revert must find nothing to resurface (a stale resume flag must not
        // revive a discarded snapshot).
        h.nowPlayingSource.emit(browserTrack())
        #expect(await eventually { h.coordinator.nowPlaying == nil })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .hidden })
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aFilteredBrowserEndingHandsBackToAPausedAppWithoutPopping() async {
        // The real-hardware bug: Spotify is paused in the background while a
        // browser plays (filtered). When the browser media ends, MediaRemote
        // hands now-playing back to the still-paused Spotify — nothing started
        // playing, so the surface must stay tucked.
        let h = CoordinatorHarness()
        let spotify = CoordinatorHarness.playingTrack()
        let spotifyPaused = CoordinatorHarness.playingTrack(isPlaying: false)

        // Establish a paused Spotify snapshot with the surface tucked away.
        h.nowPlayingSource.emit(spotify)
        _ = await eventually { h.coordinator.state == .nowPlaying(spotify, expanded: false) }
        h.nowPlayingSource.emit(spotifyPaused)
        _ = await eventually { h.coordinator.state == .nowPlaying(spotifyPaused, expanded: false) }
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        // A feed video grabs the system's now-playing (filtered): discarded.
        h.nowPlayingSource.emit(browserTrack())
        _ = await eventually { h.coordinator.nowPlaying == nil }

        // The browser media ends; focus returns to the paused Spotify.
        h.nowPlayingSource.emit(spotifyPaused)
        await settle()

        #expect(h.coordinator.state == .hidden)
        // The snapshot is still tracked, so hover/click-invoke stay functional.
        #expect(h.coordinator.nowPlaying == spotifyPaused)
    }

    @Test func aFilteredBrowserEndingHandsBackToAPlayingAppSurfaces() async {
        // Contrast: if focus returns to a PLAYING app, that is news — it pops.
        let h = CoordinatorHarness()
        let spotifyPaused = CoordinatorHarness.playingTrack(isPlaying: false)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.coordinator.state != .hidden }
        h.nowPlayingSource.emit(spotifyPaused)
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        h.nowPlayingSource.emit(browserTrack())
        _ = await eventually { h.coordinator.nowPlaying == nil }

        let resumed = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(resumed)

        #expect(await eventually { h.coordinator.state == .nowPlaying(resumed, expanded: false) })
    }

    @Test func theIncludeBrowsersFlagLetsBrowserMediaThrough() async {
        // The toggle: same pipeline, filter off.
        let h = CoordinatorHarness(ignoresBrowserMedia: false)
        let video = browserTrack()

        h.nowPlayingSource.emit(video)

        #expect(await eventually { h.coordinator.state == .nowPlaying(video, expanded: false) })
    }
}
