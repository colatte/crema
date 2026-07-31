import Testing
@testable import Crema

/// The scrub grace window: on release the user's position takes authority in
/// the same MainActor turn (optimistic write + source hint + exactly one seek
/// command), a stale stream echo cannot clobber it while every non-position
/// field still flows, a stream flowing at ≈ target hands authority back, and
/// the timeout releases honestly — the override is never left stuck.
@MainActor
struct CoordinatorScrubGraceTests {

    @Test func scrubTakesAuthorityInTheSameTurn() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }

        h.coordinator.scrub(to: 120)
        #expect(h.coordinator.nowPlaying?.position == 120)   // optimistic, no await
        #expect(h.nowPlayingSource.seeks == [120])           // the ticker re-anchor hint
        #expect(await eventually { h.media.commands == [.seek(seconds: 120)] })
    }

    @Test func aStaleEchoDuringTheGraceDoesNotMoveTheBar() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }
        h.coordinator.scrub(to: 120)

        // The pre-seek anchor still echoing (position 12), carrying a real
        // state change (paused) — the flip must land, the position must not.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 12, isPlaying: false))
        #expect(await eventually { h.coordinator.nowPlaying?.isPlaying == false })
        #expect(h.coordinator.nowPlaying?.position == 120)
    }

    @Test func theStreamFlowingAtTheTargetHandsAuthorityBack() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }
        h.coordinator.scrub(to: 120)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 121))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 121 })

        // Authority is genuinely back: a later far-away position is obeyed.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 12))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 12 })
    }

    @Test func theGraceTimeoutReleasesHonestly() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }
        h.coordinator.scrub(to: 120)

        // Advance inside the poll (the OSD suites' load-robust handshake): the
        // grace task's park can lag under the parallel suite, and an advance
        // with no sleeper is a no-op. Stale emits are held until the timer
        // fires; past the window the stream rules again — even far from the
        // target.
        #expect(await eventually {
            h.clock.advance(delay: ScrubGrace.defaultWindow)
            h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 15))
            return h.coordinator.nowPlaying?.position == 15
        })
    }

    @Test func aTrackChangeEndsTheGraceImmediately() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }
        h.coordinator.scrub(to: 120)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Time", position: 0))
        #expect(await eventually { h.coordinator.nowPlaying?.title == "Time" })
        #expect(h.coordinator.nowPlaying?.position == 0)   // the new track owns its position
    }

    @Test func aDiscardKillsTheGraceWithTheSnapshot() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }
        h.coordinator.scrub(to: 120)

        // The browser filter discards the snapshot (default: browsers ignored);
        // a dead snapshot must not retain the target.
        var browser = CoordinatorHarness.playingTrack(title: "Tab", position: 50)
        browser.sourceBundleID = "com.apple.Safari"
        h.nowPlayingSource.emit(browser)
        #expect(await eventually { h.coordinator.nowPlaying == nil })

        // A fresh same-identity track flows with no leftover override.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 40))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 40 })
    }

    @Test func aFailedSeekRollsTheOptimismBack() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }

        h.media.shouldThrow = true
        h.coordinator.scrub(to: 120)
        // The failure ends the grace and tells the source to undo its anchor.
        #expect(await eventually { h.nowPlayingSource.seekFailures == 1 })

        // With the grace gone, the stream's truth lands unchallenged.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 15))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 15 })
    }

    @Test func aStaleSeekFailureDoesNotTearDownANewerScrub() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        _ = await eventually { h.coordinator.nowPlaying != nil }

        // Two releases inside the command latency: the first seek fails after
        // the second scrub armed its own grace and anchor. Only the epoch that
        // failed may roll back — and it is stale, so nothing is torn down.
        h.media.failingSeekSeconds = 120
        h.coordinator.scrub(to: 120)
        h.coordinator.scrub(to: 130)
        // Both seeks reached the player; WHICH arrived first is not asserted,
        // because nothing promises it — each command travels its own Task and
        // hops off the actor, so the pair races (MockNowPlayingController.record).
        // The subject here survives either order: the epoch is bumped
        // synchronously by the second scrub, so the first one's failure is stale
        // whenever it lands.
        #expect(await eventually { h.media.commands.count == 2 })
        #expect(h.media.commands.contains(.seek(seconds: 120)))
        #expect(h.media.commands.contains(.seek(seconds: 130)))

        // The newer scrub's grace still holds: a stale echo carrying a real
        // state change lands the change but not the position.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 12, isPlaying: false))
        #expect(await eventually { h.coordinator.nowPlaying?.isPlaying == false })
        #expect(h.coordinator.nowPlaying?.position == 130)
        #expect(h.nowPlayingSource.seekFailures == 0)
    }

    @Test func scrubClampsTheTargetToTheTrack() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))   // duration 169
        _ = await eventually { h.coordinator.nowPlaying != nil }

        h.coordinator.scrub(to: 500)
        #expect(h.coordinator.nowPlaying?.position == 169)
        #expect(h.nowPlayingSource.seeks == [169])   // one number everywhere
        #expect(await eventually { h.media.commands == [.seek(seconds: 169)] })
    }

    @Test func scrubWithoutMediaStillSendsTheCommandOnly() async {
        let h = CoordinatorHarness()
        h.coordinator.scrub(to: 42)
        #expect(await eventually { h.media.commands == [.seek(seconds: 42)] })
        #expect(h.nowPlayingSource.seeks.isEmpty)   // no snapshot, nothing to re-anchor
    }
}
