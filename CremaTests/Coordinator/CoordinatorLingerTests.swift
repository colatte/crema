import Testing
@testable import Crema

/// Reactive now playing: a media event (track change, play/pause) surfaces the
/// compact appearance temporarily; the linger timer tucks it away; hover holds
/// and expands what is visible — a tucked surface never reacts to the pointer
/// (invocation is a click; see CoordinatorInvokeTests). Driven by the
/// injectable clock — tests never really sleep.
@MainActor
struct CoordinatorLingerTests {

    private let track = CoordinatorHarness.playingTrack()
    private let linger = Coordinator.defaultNowPlayingLinger

    private func appeared(_ h: CoordinatorHarness, linger: Double = Coordinator.defaultNowPlayingLinger) async {
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }
        // Wait until the linger actually parks: cancellations and advances in
        // the test body are deterministic only against a parked sleep.
        await h.clock.waitForSleep(delay: linger)
    }

    /// Drives the appearance to tucked (linger elapsed).
    private func tucked(_ h: CoordinatorHarness) async {
        await appeared(h)
        h.clock.advance(delay: linger)
        _ = await eventually { h.coordinator.state == .hidden }
    }

    @Test func appearanceTucksAfterTheLingerDelay() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.clock.advance(delay: linger)

        #expect(await eventually { h.coordinator.state == .hidden })
        // Media is still playing — only the surface tucked.
        #expect(h.coordinator.nowPlaying?.isPlaying == true)
        #expect(h.coordinator.mediaActive)
    }

    @Test func trackChangeResurfacesATuckedSurface() async {
        let h = CoordinatorHarness()
        await tucked(h)

        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)

        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })
    }

    @Test func positionTickDoesNotResurfaceATuckedSurface() async {
        let h = CoordinatorHarness()
        await tucked(h)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying?.position == 11)
    }

    @Test func playPauseFlipResurfacesInBothDirections() async {
        let h = CoordinatorHarness()
        await tucked(h)

        // Pause: a compact appearance reflecting the paused state.
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) })

        await h.clock.waitForSleep(delay: linger)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })

        // Resume: appears again, playing.
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func hoverHoldsTheAppearanceAndHoverOutResumesTheTuck() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.coordinator.hover(true)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        // The linger was cancelled: nothing left to tuck the surface.
        #expect(await eventually { h.clock.pendingSleeps == 0 })

        h.coordinator.hover(false)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        // Hover-out buys the short re-linger, not a fresh full one (R5).
        await h.clock.waitForSleep(delay: Coordinator.hoverExitRelinger)
        h.clock.advance(delay: Coordinator.hoverExitRelinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func hoverOverATuckedSurfaceDoesNothing() async {
        let h = CoordinatorHarness()
        await tucked(h)

        // The accidental-appearance fix: an empty region never reacts to the
        // pointer — invocation is a click (or a media event), never hover.
        h.coordinator.hover(true)
        await settle()

        #expect(h.coordinator.state == .hidden)
    }

    @Test func hoverIntentOverATuckedSurfaceDoesNothingEvenAfterTheDwell() async {
        let h = CoordinatorHarness()
        await tucked(h)

        // The debounced path (the notch's) must be equally inert: even a
        // pointer that dwells on the empty region surfaces nothing.
        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)
        h.clock.advance(delay: Coordinator.defaultHoverIntentDelay)
        await settle()

        #expect(h.coordinator.state == .hidden)
    }

    @Test func hoverDoesNotResurfacePausedMedia() async {
        let h = CoordinatorHarness()
        await appeared(h)
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        // The pause event must land (restarting the linger) before advancing.
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) })
        await h.clock.waitForSleep(delay: linger)
        h.clock.advance(delay: linger)
        _ = await eventually { h.coordinator.state == .hidden }
        #expect(!h.coordinator.mediaActive)

        h.coordinator.hover(true)
        await settle()

        #expect(h.coordinator.state == .hidden)
    }

    @Test func hudOverATuckedSurfaceRevertsToHidden() async {
        let h = CoordinatorHarness()
        await tucked(h)

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        // The HUD is not a media event: it must not resurrect the appearance.
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func mediaEventDuringHUDResurfacesAfterTheRevert() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        // A track change lands while the HUD owns the surface: the revert shows
        // the pending appearance instead of dropping it.
        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.nowPlaying == next })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })
    }

    @Test func positionTickWhileVisibleDoesNotRestartTheLinger() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 11 })

        // Exactly one linger was ever requested: ticks must not re-park it, or
        // the surface never tucks during playback.
        #expect(h.clock.delays.filter { $0 == linger }.count == 1)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func artworkArrivingLaterDoesNotResurfaceATuckedSurface() async {
        let h = CoordinatorHarness()
        await tucked(h)

        // Same track, artwork bytes filled in a beat later (slow fetch): a
        // refinement, not an event — the surface stays tucked.
        var withArtwork = track
        withArtwork.artworkData = [1, 2, 3]
        h.nowPlayingSource.emit(withArtwork)
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying?.artworkData != nil)
    }

    @Test func artworkArrivingWhileVisibleRefreshesTheAppearance() async {
        let h = CoordinatorHarness()
        await appeared(h)

        var withArtwork = track
        withArtwork.artworkData = [1, 2, 3]
        h.nowPlayingSource.emit(withArtwork)

        #expect(await eventually { h.coordinator.state == .nowPlaying(withArtwork, expanded: false) })
    }

    @Test func chainedHUDsOverAVisibleAppearanceStillResurface() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.4))
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func aStrayPointerDuringAHUDOverTuckedDoesNotResurrectOnRevert() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        // A cursor resting on the region while the HUD shows is not a media
        // event: it holds the HUD (docs/DECISIONS.md: hud-capsule-track), but
        // reviving the tucked appearance from it is the accidental-appearance
        // class the click-invoke model removed. After the pointer leaves, the
        // HUD reverts to hidden; only a pending event (or a click) earns a
        // resurface.
        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)
        h.clock.advance(delay: Coordinator.defaultHoverIntentDelay)
        await settle()

        h.coordinator.hoverIntent(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func pauseDuringAHUDResurfacesThePausedAppearanceOnRevert() async {
        let h = CoordinatorHarness()
        await appeared(h)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.nowPlaying == paused })

        // The pause flip earns its appearance on the revert, exactly as it
        // would outside the HUD; the linger then bounds it.
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) })

        await h.clock.waitForSleep(delay: linger)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aNewPausedIdentityDuringAHUDIsNotResurfacedOnRevert() async {
        // Contrast with pauseDuringAHUDResurfacesThePausedAppearanceOnRevert: a
        // pause flip of the visible track earns its appearance on the revert, but
        // a fresh paused identity landing during the HUD is not news — nothing
        // started playing — so the revert hands back to hidden, never surfacing
        // an appearance the app had not shown.
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.nowPlaying == paused })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func streamEndDropsTheGhostSnapshot() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.nowPlayingSource.finish()

        // No source left: the snapshot would be a frozen ghost (dead controls),
        // and hover must stop arming.
        #expect(await eventually { h.coordinator.nowPlaying == nil })
        #expect(await eventually { !h.coordinator.mediaActive })
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func lingerIsConfigurableAndHasOneDefault() async {
        #expect(Coordinator.defaultNowPlayingLinger == 3.0)

        let h = CoordinatorHarness(nowPlayingLinger: 0.5)
        await appeared(h, linger: 0.5)
        h.clock.advance(delay: 0.5)
        #expect(await eventually { h.coordinator.state == .hidden })
    }
}
