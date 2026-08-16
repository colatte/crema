import Testing
@testable import Crema

/// Hover-intent: expansion waits behind a delay, collapse debounces,
/// both are cancellable and rechecked. Driven by the injectable clock; the test
/// never really sleeps.
@MainActor
struct CoordinatorHoverIntentTests {

    private let track = CoordinatorHarness.playingTrack()

    /// A harness already showing the compact now-playing surface.
    private func showingCompact(
        nowPlayingLinger: Double = Coordinator.defaultNowPlayingLinger,
        hoverIntentDelay: Double = Coordinator.defaultHoverIntentDelay,
        hoverOutDebounce: Double = Coordinator.defaultHoverOutDebounce
    ) async -> CoordinatorHarness {
        let h = CoordinatorHarness(
            nowPlayingLinger: nowPlayingLinger,
            hoverIntentDelay: hoverIntentDelay,
            hoverOutDebounce: hoverOutDebounce
        )
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }
        // Wait until the appearance's linger parks, so cancellation counts in
        // the test bodies are deterministic across optimization levels.
        await h.clock.waitForSleep(delay: nowPlayingLinger)
        return h
    }

    /// Drives the surface all the way to expanded (intent delay elapsed).
    private func expand(_ h: CoordinatorHarness) async {
        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep()
        h.clock.advance()
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: true) }
    }

    @Test func expandsOnlyAfterTheIntentDelay() async {
        let h = await showingCompact()

        h.coordinator.hoverIntent(true)
        // Deferred behind the delay: still compact until the clock advances.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))

        await h.clock.waitForSleep()
        #expect(h.clock.delays.last == Coordinator.defaultHoverIntentDelay)

        h.clock.advance()
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: true) })
    }

    @Test func leavingBeforeTheDelayCancelsTheExpansion() async {
        let h = await showingCompact()

        h.coordinator.hoverIntent(true)   // also cancels the appearance's linger
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)

        h.coordinator.hoverIntent(false)   // pointer left before the intent fired
        // Two cancellations so far: the linger (held by the pointer) + the intent.
        #expect(await eventually { h.clock.cancelledCount == 2 })

        // The pending expansion never runs; the debounce is a no-op (already compact).
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)
        h.clock.advance(delay: Coordinator.defaultHoverOutDebounce)
        await settle()
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
    }

    @Test func collapsesOnlyAfterTheOutDebounce() async {
        let h = await showingCompact()
        await expand(h)

        h.coordinator.hoverIntent(false)
        // Still expanded until the debounce elapses.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        await h.clock.waitForSleep()
        #expect(h.clock.delays.last == Coordinator.defaultHoverOutDebounce)

        h.clock.advance()
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func reenteringDuringTheDebounceKeepsItExpanded() async {
        let h = await showingCompact()
        await expand(h)   // one cancellation: the linger, held by the pointer

        h.coordinator.hoverIntent(false)   // start the collapse debounce
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)

        h.coordinator.hoverIntent(true)    // pointer came back: cancel the collapse
        #expect(await eventually { h.clock.cancelledCount == 2 })

        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)
        h.clock.advance(delay: Coordinator.defaultHoverIntentDelay)
        await settle()
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
    }

    @Test func tuckingAfterHoverOutResetsSoResumingComesBackCompact() async {
        let h = await showingCompact()
        await expand(h)   // committed hover: isHovering true, expanded

        // Pause while hovering: the appearance stays under the pointer, paused.
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: true) })

        // Pointer leaves → collapse + linger → tucked away.
        h.coordinator.hoverIntent(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)
        h.clock.advance(delay: Coordinator.defaultHoverOutDebounce)
        // Hover-out buys the short re-linger, not a fresh full one (R5).
        await h.clock.waitForSleep(delay: Coordinator.hoverExitRelinger)
        h.clock.advance(delay: Coordinator.hoverExitRelinger)
        #expect(await eventually { h.coordinator.state == .hidden })

        // Resume with no pointer on the notch: it must return compact.
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func lingerNeverTucksWhileThePointerIsInside() async {
        let h = await showingCompact(nowPlayingLinger: 0.05)
        // A pointer graze: enter (holds the linger), leave before the intent
        // fires, debounce commits the no-op collapse and restarts the linger.
        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)
        h.coordinator.hoverIntent(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)
        h.clock.advance(delay: Coordinator.defaultHoverOutDebounce)

        // The restarted linger tucks the surface once the pointer is away.
        await h.clock.waitForSleep(delay: 0.05)
        h.clock.advance(delay: 0.05)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    /// A completed intent cycle leaves no residue in the immediate path: the
    /// fired task must not stay retained, or `hover(false)` on an immediate
    /// style would divert to the debounced collapse (the mixed-style setup:
    /// debounced gesture on the notch, immediate Card on another display,
    /// one Coordinator).
    @Test func aCompletedIntentCycleDoesNotDebounceALaterImmediateHover() async {
        let h = await showingCompact()
        await expand(h)

        // Complete the cycle: the collapse intent fires too.
        h.coordinator.hoverIntent(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)
        h.clock.advance(delay: Coordinator.defaultHoverOutDebounce)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

        // Immediate-style gesture: both edges commit at once. The clock stays
        // parked — any diversion to the debounced path would leave the state
        // expanded here, waiting on an advance this test never gives.
        h.coordinator.hover(true)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        h.coordinator.hover(false)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
    }

    /// The control pair: a genuinely in-flight debounced gesture still routes
    /// `hover(false)` through the intent path — the fix narrows the guard to
    /// live tasks, it does not remove it.
    @Test func hoverOutDuringAnInFlightIntentStillTakesTheDebouncedPath() async {
        let h = await showingCompact()

        h.coordinator.hover(true)   // immediate expand
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        h.coordinator.hoverIntent(true)   // debounced gesture now in flight
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)

        h.coordinator.hover(false)
        // Diverted: still expanded until the out-debounce elapses.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverOutDebounce)
        h.clock.advance(delay: Coordinator.defaultHoverOutDebounce)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func delaysAreConfigurable() async {
        let h = await showingCompact(hoverIntentDelay: 0.5, hoverOutDebounce: 0.05)

        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep()
        #expect(h.clock.delays.last == 0.5)
    }
}
