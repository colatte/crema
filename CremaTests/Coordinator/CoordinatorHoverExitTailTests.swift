import Testing
@testable import Crema

/// What a finished hover leaves behind: the shortened tail (hoverExitRelinger)
/// the appearance keeps until a real event replaces it. A refinement — artwork
/// or a duration landing a beat later — restarts the tuck timer through the
/// plain path, and restarting it from the full linger handed the graze back the
/// whole 3 s it had just given up, so the surface outstayed its own rule for as
/// long as content kept trickling in.
///
/// Driven by the injectable clock; the test never really sleeps. The assertions
/// read the clock's PARK RECORD rather than `delays.last`, because the hover
/// exit's own park carries the same number the correct restart does.
@MainActor
struct CoordinatorHoverExitTailTests {

    private let track = CoordinatorHarness.playingTrack()
    private let linger = Coordinator.defaultNowPlayingLinger

    /// A visible compact appearance whose linger has parked — cancellations and
    /// advances below are deterministic only against a parked sleep.
    private func appeared(_ h: CoordinatorHarness) async {
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        await h.clock.waitForSleep(delay: linger)
    }

    /// The same track with artwork filled in: a refinement, never an event.
    private func refined() -> NowPlaying {
        var copy = track
        copy.artworkData = [1, 2, 3]
        return copy
    }

    @Test func aRefinementAfterHoverOutDoesNotStretchTheShortTail() async {
        let h = CoordinatorHarness()
        await appeared(h)

        h.coordinator.hover(true)    // holds the appearance, cancels the linger
        h.coordinator.hover(false)   // the exit buys hoverExitRelinger, not a full one
        await h.clock.waitForSleep(delay: Coordinator.hoverExitRelinger)

        let withArtwork = refined()
        h.nowPlayingSource.emit(withArtwork)
        #expect(await eventually { h.coordinator.state == .nowPlaying(withArtwork, expanded: false) })

        #expect(await eventually { h.clock.delays.count == 3 })
        #expect(h.clock.delays == [linger, Coordinator.hoverExitRelinger, Coordinator.hoverExitRelinger])

        h.clock.advance(delay: Coordinator.hoverExitRelinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aMediaEventAfterHoverOutStillEarnsTheFullLinger() async {
        // The control: the cap belongs to the tail a hover left, not to the
        // appearance for the rest of its life. A track change is news and re-arms
        // the whole duration — capping that too would make every appearance
        // following a graze a short one.
        let h = CoordinatorHarness()
        await appeared(h)

        h.coordinator.hover(true)
        h.coordinator.hover(false)
        await h.clock.waitForSleep(delay: Coordinator.hoverExitRelinger)

        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })

        #expect(await eventually { h.clock.delays.count == 3 })
        #expect(h.clock.delays == [linger, Coordinator.hoverExitRelinger, linger])

        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func anInvokedAppearanceKeepsItsLongTailThroughHoverAndRefinement() async {
        // The second control, for the exemption the cap must not swallow: the
        // click-invoked appearance keeps its full tail through a hover cycle
        // (its pointer sits on the surface from the click itself), and a
        // refinement must not shorten it either.
        let h = CoordinatorHarness()
        await appeared(h)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })

        h.coordinator.invoke()
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)

        h.coordinator.hover(true)
        h.coordinator.hover(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)

        let withArtwork = refined()
        h.nowPlayingSource.emit(withArtwork)
        #expect(await eventually { h.coordinator.nowPlaying == withArtwork })

        #expect(await eventually { h.clock.delays.count == 4 })
        #expect(!h.clock.delays.contains(Coordinator.hoverExitRelinger))
        h.clock.advance(delay: Coordinator.defaultInvokedLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }
}
