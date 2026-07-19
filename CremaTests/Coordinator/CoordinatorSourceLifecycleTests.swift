import Testing
@testable import Crema

/// The ghost-discard seam (audit S6): when the active now-playing source ends
/// without the outer stream finishing — a chain failover, a total outage, or a
/// deliberate A4 promotion — the Coordinator drops the stale snapshot rather
/// than keep it armed for hover/click. The chain fires this in production; here
/// it is driven directly, with mocks.
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
}
