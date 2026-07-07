import Testing
@testable import Crema

/// Click-invoke: the deliberate way to surface a tucked appearance. A click on
/// the (empty) style region opens the expanded player directly (the user
/// clicked to see/control) with a longer linger than the reactive one;
/// closing is spatial — pointer leaves, it collapses, the linger tucks it.
/// Driven by the injectable clock — tests never really sleep.
@MainActor
struct CoordinatorInvokeTests {

    private let track = CoordinatorHarness.playingTrack()

    /// Drives the appearance to tucked (reactive linger elapsed).
    private func tucked(_ h: CoordinatorHarness) async {
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }
    }

    @Test func invokeOpensTheExpandedPlayerWithTheLongerLinger() async {
        let h = CoordinatorHarness()
        await tucked(h)

        h.coordinator.invoke()

        // Expanded directly — the user clicked to see/control; the compact
        // would only flash on its way to the hover expansion.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        // The user asked for it: the appearance earns the invoked linger, not
        // the reactive one. With no pointer ever committing a hover, the tuck
        // must end even the expanded form (nothing is holding it).
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)
        h.clock.advance(delay: Coordinator.defaultInvokedLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func invokeWithoutMediaDoesNothing() async {
        let h = CoordinatorHarness()

        h.coordinator.invoke()
        await settle()

        #expect(h.coordinator.state == .hidden)
    }

    @Test func invokeWithPausedMediaDoesNothing() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state != .hidden }
        let paused = CoordinatorHarness.playingTrack(isPlaying: false)
        h.nowPlayingSource.emit(paused)
        _ = await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) }
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        _ = await eventually { h.coordinator.state == .hidden }

        // Paused media is not click-invokable — the same decision as the old
        // paused-resurface rule: only a media event re-earns an appearance.
        h.coordinator.invoke()
        await settle()

        #expect(h.coordinator.state == .hidden)
    }

    @Test func invokeWhileASurfaceIsVisibleIsANoOp() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(track)
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)

        h.coordinator.invoke()
        await settle()

        // Still the same appearance on the same reactive linger — the click
        // routed to the visible surface's controls, not to invocation.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        #expect(!h.clock.delays.contains(Coordinator.defaultInvokedLinger))
    }

    @Test func pointerExitCollapsesTheInvokedPlayerAndTheInvokedTuckEndsIt() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.coordinator.invoke()
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)

        // The full chain: click → expanded → pointer holds → exit → compact →
        // tuck. The linger is a property of the appearance: an invoked one
        // keeps its longer duration through hover cycles — in production the
        // click lands with the pointer already on the fresh surface, so the
        // initial timer is always replaced by a hover cycle.
        h.coordinator.hover(true)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        #expect(await eventually { h.clock.pendingSleeps == 0 })   // pointer holds the tuck

        h.coordinator.hover(false)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)
        h.clock.advance(delay: Coordinator.defaultInvokedLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func invokeSurvivesTheReentrantHoverTheStateWriteTriggers() async {
        // Production wiring: the state write's didSet runs the frame pass,
        // which arms the hover monitor, whose immediate sample finds the
        // pointer inside (the click landed in that rect) and commits a hover
        // re-entrantly — before invoke() even starts its timer. The invoked
        // duration must survive that cycle.
        let h = CoordinatorHarness()
        await tucked(h)

        var reentered = false
        h.coordinator.onPresentationChange = { [coordinator = h.coordinator] in
            if !reentered, case .nowPlaying = coordinator.state {
                reentered = true
                coordinator.hover(true)   // the monitor's arming sample
            }
        }
        h.coordinator.invoke()
        h.coordinator.onPresentationChange = nil

        // Already expanded by the invoke itself; the re-entrant hover only
        // commits the hold.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        // Pointer leaves: the tuck must run on the invoked linger — the
        // hardcoded-reactive restart was exactly the bug that made the 5 s
        // unreachable in production.
        h.coordinator.hover(false)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)
        h.clock.advance(delay: Coordinator.defaultInvokedLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aMediaEventDuringAnInvokedAppearanceResetsToTheReactiveLinger() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.coordinator.invoke()
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)

        // A track change is a reactive appearance — it earns the reactive
        // linger even over an invoked one.
        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })
        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aRefinementBeforeTheHoverCommitsDoesNotCollapseTheInvokedPlayer() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.coordinator.invoke()
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        // Artwork lands a beat after the click, while the pointer is still
        // inside the intent window (no committed hover): a refinement must
        // preserve the expansion, not fold the player the user just opened.
        var withArtwork = track
        withArtwork.artworkData = [1, 2, 3]
        h.nowPlayingSource.emit(withArtwork)

        #expect(await eventually { h.coordinator.state == .nowPlaying(withArtwork, expanded: true) })
    }

    @Test func aMediaEventDuringAHUDOverAnInvokedAppearanceResetsTheLinger() async {
        let h = CoordinatorHarness()
        await tucked(h)
        h.coordinator.invoke()
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)

        // A HUD interrupts the invoked player; a track change lands during
        // the HUD. The revert shows the new event's appearance — a reactive
        // one, with the reactive linger, exactly as it would surface outside
        // the HUD (the invoked 5 s must not leak onto it).
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })
        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.nowPlaying == next })

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })

        await h.clock.waitForSleep(delay: Coordinator.defaultNowPlayingLinger)
        h.clock.advance(delay: Coordinator.defaultNowPlayingLinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func exposesTheDefaultInvokedLinger() {
        #expect(Coordinator.defaultInvokedLinger == 5.0)
        // The invoked appearance must outlast the reactive one — the user
        // asked for it.
        #expect(Coordinator.defaultInvokedLinger > Coordinator.defaultNowPlayingLinger)
    }
}
