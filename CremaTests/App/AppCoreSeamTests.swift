import Testing
@testable import Crema

/// The S6 ghost-discard seam AppCore installs between the now-playing chain and
/// the Coordinator. The two halves are pinned in isolation elsewhere — the chain
/// fires onActiveSourceEnded (ChainedNowPlayingSourceTests) and the Coordinator
/// discards on activeNowPlayingSourceEnded (CoordinatorSourceLifecycleTests) —
/// but the wiring that joins them lived only in the composition root, untested:
/// break the seam and both isolated suites stay green while the ghost resurrects
/// in production. This drives the real seam end to end, over the SAME wiring
/// AppCore uses (AppCore.wireActiveSourceEnded), with mocks on both sides.
@MainActor
struct AppCoreSeamTests {

    @Test func theSeamDropsTheCoordinatorGhostWhenTheChainSourceDies() async {
        let h = CoordinatorHarness()
        let adapter = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { true }, makeSource: { adapter }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock()
        )
        // The exact wiring AppCore installs — the seam under test.
        AppCore.wireActiveSourceEnded(from: chain, to: h.coordinator)
        let chainIterator = BoundedStreamIterator(chain.updates)

        // The Coordinator holds a ghost from its own source; the chain is live,
        // forwarding from its adapter.
        let ghost = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(ghost)
        _ = await eventually { h.coordinator.state == .nowPlaying(ghost, expanded: false) }
        adapter.emit(CoordinatorHarness.playingTrack(title: "chain"))
        _ = await chainIterator.next()   // the chain is forwarding

        // The chain's active source dies without the outer stream finishing: the
        // seam must reach the Coordinator and drop the ghost.
        adapter.finish()

        #expect(await eventually { h.coordinator.nowPlaying == nil })
        #expect(!h.coordinator.mediaActive)

        chain.stop()
    }
}
