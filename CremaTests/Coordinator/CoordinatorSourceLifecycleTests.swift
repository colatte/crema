import Testing
@testable import Crema

/// The ghost-discard seam (docs/DECISIONS.md: ghost-discard): when the active
/// now-playing source ends without the outer stream finishing — a chain
/// failover, a total outage, or a deliberate promotion — the Coordinator drops
/// the stale snapshot rather than keep it armed for hover/click. The chain fires
/// this in production; here it is driven directly, with mocks.
@MainActor
struct CoordinatorSourceLifecycleTests {

    private let track = CoordinatorHarness.playingTrack()

    @Test func anEndedSourceDiscardsTheTuckedGhostAndDisarmsInvoke() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }
        // Let the surface tuck: the ghost now lives only as mediaActive +
        // nowPlaying, arming click-invoke.
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }
        #expect(h.coordinator.mediaActive)

        // The active source dies (failover / outage / promotion).
        h.coordinator.activeNowPlayingSourceEnded()

        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
        h.coordinator.invoke()
        #expect(h.coordinator.state == .hidden)   // invoke is now a no-op
    }

    @Test func anEndedSourceHidesAVisibleGhostSurface() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        h.coordinator.activeNowPlayingSourceEnded()

        #expect(await eventually { h.coordinator.state == .hidden })
        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aNewSourceRebuildsAfterTheGhostIsDiscarded() async {
        let h = CoordinatorHarness()
        let first = CoordinatorHarness.playingTrack(title: "A")
        h.nowPlayingSource.emit(first)
        _ = await eventually { h.coordinator.state == .nowPlaying(first, expanded: false) }

        // Failover: the old source ended; the new one takes over and emits
        // through the same update path, rebuilding the state.
        h.coordinator.activeNowPlayingSourceEnded()
        #expect(h.coordinator.nowPlaying == nil)

        let second = CoordinatorHarness.playingTrack(title: "B")
        h.nowPlayingSource.emit(second)

        #expect(await eventually { h.coordinator.state == .nowPlaying(second, expanded: false) })
        #expect(h.coordinator.mediaActive)
    }

    @Test func aTotalOutageDiscardsAndLeavesNothingArmed() async {
        // No source emits after the end — the discard stands (the menu's
        // degraded signal is the chain's onActiveChange, tested there).
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        h.coordinator.activeNowPlayingSourceEnded()
        await settle()

        #expect(h.coordinator.state == .hidden)
        #expect(h.coordinator.nowPlaying == nil)
        #expect(!h.coordinator.mediaActive)
    }

    @Test func aFailoverDuringAHUDDoesNotResurfaceThePromotedPausedSnapshot() async {
        // The failover twin of the browser case (CoordinatorBrowserFilterTests):
        // the discard lands while a HUD owns the surface, so its hide() never runs
        // and the promise armed by the interrupted appearance is the only thing
        // that could open a card. The promoted source's first snapshot is paused —
        // nothing started playing, so it arms no resume of its own — and the revert
        // must hand back to hidden.
        let h = CoordinatorHarness()
        let volumeHUD = SystemHUD(kind: .volume, value: 0.5)
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(volumeHUD)
        #expect(await eventually { h.coordinator.state == .hud(volumeHUD) })

        h.coordinator.activeNowPlayingSourceEnded()
        #expect(h.coordinator.nowPlaying == nil)
        #expect(h.coordinator.state == .hud(volumeHUD))   // the HUD still owns the surface

        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.nowPlaying == paused })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        _ = await eventually { h.coordinator.state != .hud(volumeHUD) }
        #expect(h.coordinator.state == .hidden)
    }

    @Test func aPlayingSnapshotAfterADiscardDuringAHUDStillResurfaces() async {
        // Control for the two negative tests: the discard CLEARS the promise, it
        // does not blacklist the resume. A snapshot that is news re-earns it in the
        // .hud branch and still gets its appearance on the revert — without this,
        // a "fix" that latched the discard (or that stopped arming altogether)
        // would leave both negative tests green while pinning nothing.
        let h = CoordinatorHarness()
        let volumeHUD = SystemHUD(kind: .volume, value: 0.5)
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(volumeHUD)
        #expect(await eventually { h.coordinator.state == .hud(volumeHUD) })

        h.coordinator.activeNowPlayingSourceEnded()
        #expect(h.coordinator.nowPlaying == nil)

        let promoted = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(promoted)
        #expect(await eventually { h.coordinator.nowPlaying == promoted })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(promoted, expanded: false) })
    }
}
