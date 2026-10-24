import Testing
@testable import Crema

/// The welcome tour's showcase: the player held up while the tour talks about
/// it — the player's own track when there is one, a sample when there is none —
/// with no tuck until the tour lets go, and no command ever reaching a player on
/// the sample's behalf.
@MainActor
struct CoordinatorShowcaseTests {

    private let track = CoordinatorHarness.playingTrack()
    private let sample = NowPlaying(title: "Your music shows up here", artist: "Crema", isPlaying: true, position: 0)

    @Test func withNothingPlayingTheSampleIsShownAndHeldWithNoTuck() async {
        let h = CoordinatorHarness()

        h.coordinator.showcase(sample: sample)
        await settle()

        #expect(h.coordinator.state == .nowPlaying(sample, expanded: false))
        #expect(h.coordinator.showsSample)
        // Held: the reactive linger never starts, so nothing on the clock can
        // tuck it while the tour is still talking about it.
        #expect(!h.clock.isParked(delay: Coordinator.defaultNowPlayingLinger))
        #expect(h.clock.pendingSleeps == 0)
    }

    @Test func withATrackPlayingTheTrackIsShownInsteadOfTheSample() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })

        h.coordinator.showcase(sample: sample)

        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        #expect(!h.coordinator.showsSample)
    }

    /// The sample is no player's: every transport intent is refused at the
    /// Coordinator, not only greyed out in the skin. The real track emitted
    /// afterwards is the barrier — its toggle is recorded, so the sample's
    /// refusals were not merely still in flight.
    @Test func noCommandReachesAPlayerOnTheSamplesBehalf() async {
        let h = CoordinatorHarness()
        h.coordinator.showcase(sample: sample)
        #expect(!h.coordinator.controlsEnabled)
        #expect(!h.coordinator.skipControlsEnabled)

        h.coordinator.togglePlayPause()
        h.coordinator.nextTrack()
        h.coordinator.previousTrack()
        h.coordinator.scrub(to: 30)

        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        #expect(h.coordinator.controlsEnabled)
        h.coordinator.togglePlayPause()
        #expect(await eventually { !h.media.commands.isEmpty })
        #expect(h.media.commands == [.togglePlayPause])
    }

    @Test func aTrackArrivingTakesTheSamplesPlaceAndStaysHeld() async {
        let h = CoordinatorHarness()
        h.coordinator.showcase(sample: sample)

        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        #expect(!h.coordinator.showsSample)
        await settle()
        #expect(!h.clock.isParked(delay: Coordinator.defaultNowPlayingLinger))
    }

    /// The track the showcase stood on goes away mid-tour: the sample comes back
    /// rather than the player vanishing under a step that is talking about it.
    @Test func mediaDroppedMidShowcaseBringsTheSampleBack() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        h.coordinator.showcase(sample: sample)

        h.coordinator.activeNowPlayingSourceEnded()

        #expect(h.coordinator.state == .nowPlaying(sample, expanded: false))
        #expect(h.coordinator.showsSample)
    }

    @Test func endingTheShowcaseRemovesTheSampleAtOnce() {
        let h = CoordinatorHarness()
        h.coordinator.showcase(sample: sample)

        h.coordinator.endShowcase()

        #expect(h.coordinator.state == .hidden)
        #expect(!h.coordinator.showsSample)
    }

    @Test func endingTheShowcaseHandsARealTrackBackToItsTuck() async {
        let h = CoordinatorHarness()
        h.coordinator.showcase(sample: sample)
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.coordinator.endShowcase()

        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    /// A HUD rising over the held sample and reverting gives it back, untucked:
    /// the revert re-arms the tuck everywhere else, and the hold has to win here.
    @Test func aHUDRevertDoesNotTuckTheHeldPlayer() async {
        let h = CoordinatorHarness()
        h.coordinator.showcase(sample: sample)
        let press = SystemHUD(kind: .volume, value: 0.4)

        h.hudSource.emit(press)
        #expect(await eventually { h.coordinator.state == .hud(press) })
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(sample, expanded: false) })
        await settle()
        #expect(!h.clock.isParked(delay: Coordinator.defaultNowPlayingLinger))
    }

    @Test func endingAShowcaseThatWasNeverHeldChangesNothing() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.coordinator.endShowcase()

        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
    }
}
