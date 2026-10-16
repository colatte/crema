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
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

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
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        // The feed video steals focus while the HUD owns the surface: the
        // revert must find nothing to resurface (the appearance under the HUD
        // goes with the snapshot it showed).
        h.nowPlayingSource.emit(browserTrack())
        #expect(await eventually { h.coordinator.nowPlaying == nil })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .hidden })
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aPausedHandbackDuringAHUDIsNotSurfacedByTheDiscardedAppearance() async {
        // The repopulation half of aBrowserTakeoverDuringAHUDLeavesNothingToResurface:
        // that one stops at nowPlaying == nil, and it is the REPOPULATION that
        // would show up in an appearance the discard should have taken down. The
        // HUD rose over a visible appearance, the browser discard drops the
        // snapshot it showed, and the app handed the focus next is paused —
        // earning no appearance of its own. The card must stay shut.
        let h = CoordinatorHarness()
        let volumeHUD = SystemHUD(kind: .volume, value: 0.5)
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        // Asserted, not discarded: with no appearance under the HUD there is
        // nothing to take down, and the test would pass for the wrong reason.
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(volumeHUD)
        #expect(await eventually { h.coordinator.state == .hud(volumeHUD) })

        h.nowPlayingSource.emit(browserTrack())
        #expect(await eventually { h.coordinator.nowPlaying == nil })

        // The feed video ends; now-playing lands on a different, paused player.
        let stranger = CoordinatorHarness.playingTrack(title: "Us and Them", isPlaying: false)
        h.nowPlayingSource.emit(stranger)
        #expect(await eventually { h.coordinator.nowPlaying == stranger })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        // Waiting for the state to LEAVE the HUD fails loud with the wrong value in
        // one hop, instead of burning the whole deadline on a timeout.
        #expect(await eventually { h.coordinator.state != .hud(volumeHUD) })
        #expect(h.coordinator.state == .hidden)
        // The snapshot is still tracked, so hover/click-invoke stay functional.
        #expect(h.coordinator.nowPlaying == stranger)
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
        #expect(await eventually { h.coordinator.state == .nowPlaying(spotify, expanded: false) })
        h.nowPlayingSource.emit(spotifyPaused)
        #expect(await eventually { h.coordinator.state == .nowPlaying(spotifyPaused, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })

        // A feed video grabs the system's now-playing (filtered): discarded.
        h.nowPlayingSource.emit(browserTrack())
        #expect(await eventually { h.coordinator.nowPlaying == nil })

        // The browser media ends; focus returns to the paused Spotify.
        h.nowPlayingSource.emit(spotifyPaused)
        // The snapshot is still tracked, so hover/click-invoke stay functional;
        // its arrival is also the barrier for the negative, decided in the same pass.
        #expect(await eventually { h.coordinator.nowPlaying == spotifyPaused })

        #expect(h.coordinator.state == .hidden)
    }

    @Test func aFilteredBrowserEndingHandsBackToAPlayingAppSurfaces() async {
        // Contrast: if focus returns to a PLAYING app, that is news — it pops.
        let h = CoordinatorHarness()
        let spotifyPaused = CoordinatorHarness.playingTrack(isPlaying: false)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.coordinator.state != .hidden })
        h.nowPlayingSource.emit(spotifyPaused)
        // The pause lands before the linger is awaited: the playing track's linger
        // has the same delay, so the wait could take that one, and the pause would
        // then re-arm a linger the clock never advances.
        #expect(await eventually { h.coordinator.state == .nowPlaying(spotifyPaused, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })

        h.nowPlayingSource.emit(browserTrack())
        #expect(await eventually { h.coordinator.nowPlaying == nil })

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
