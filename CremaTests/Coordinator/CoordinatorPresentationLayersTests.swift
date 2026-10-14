import Testing
@testable import Crema

/// The two layers under the projection every existing surface draws: a HUD rises
/// over the appearance without taking it down, the appearance keeps taking
/// events under it, and its tuck waits for the revert. A pointer holds only the
/// layers its surface draws, so a surface drawing one layer reaches that layer
/// alone. Driven by the injectable clock; the tests never really sleep.
@MainActor
struct CoordinatorPresentationLayersTests {

    private let track = CoordinatorHarness.playingTrack()
    private let hud = SystemHUD(kind: .volume, value: 0.5)
    private let linger = Coordinator.defaultNowPlayingLinger
    private let revert = Coordinator.defaultHUDRevertDelay

    /// A visible compact appearance whose linger has parked.
    private func appeared(_ h: CoordinatorHarness) async {
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        await h.clock.waitForSleep(delay: linger)
    }

    /// Media playing, appearance tucked.
    private func tucked(_ h: CoordinatorHarness) async {
        await appeared(h)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    /// The HUD up, its revert timer parked.
    private func hudUp(_ h: CoordinatorHarness) async {
        h.hudSource.emit(hud)
        #expect(await eventually { h.coordinator.layers.hud == hud })
        await h.clock.waitForSleep(delay: revert)
    }

    @Test func aHUDRisesOverTheAppearanceWithoutTakingItDown() async {
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)

        #expect(h.coordinator.layers == PresentationLayers(nowPlaying: .init(track: track, expanded: false), hud: hud))
        #expect(h.coordinator.state == .hud(hud))
    }

    @Test func aHUDOverATuckedAppearanceBringsNoneWithIt() async {
        let h = CoordinatorHarness()
        await tucked(h)
        await hudUp(h)

        #expect(h.coordinator.layers == PresentationLayers(hud: hud))
    }

    @Test func aMediaEventUnderTheHUDReachesTheAppearanceAtOnce() async {
        // A surface drawing the appearance alone shows the event while the HUD
        // is still up elsewhere; a surface drawing both shows it on the revert.
        let h = CoordinatorHarness()
        await tucked(h)
        await hudUp(h)

        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)

        #expect(await eventually { h.coordinator.layers.nowPlaying == .init(track: next, expanded: false) })
        #expect(h.coordinator.state == .hud(hud))
    }

    @Test func theAppearanceUnderTheHUDKeepsNoTuckTimerUntilTheRevert() async {
        // The event under the HUD owes the appearance a fresh linger, and the
        // revert is what arms it: a pointer holding the HUD past that linger must
        // not find the appearance tucked from under the HUD, gone before a surface
        // drawing both ever showed it. The park record is read after the tuck it
        // ends with, so a linger parked under the HUD has had every chance to
        // land in it.
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)
        h.coordinator.hover(true, on: .hud)

        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.layers.nowPlaying?.track == next })

        h.coordinator.hover(false, on: .hud)
        await h.clock.waitForSleep(delay: revert)
        h.clock.advance(delay: revert)
        #expect(await eventually { h.coordinator.state == .nowPlaying(next, expanded: false) })
        await h.clock.waitForSleep(delay: linger)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })

        #expect(h.clock.delays == [linger, revert, revert, linger])
    }

    @Test func theRevertBringsTheAppearanceBackInOneWrite() async {
        // The WindowManager's frame pass runs inside every write: a revert split
        // in two would place a frame for a state that never existed, the HUD gone
        // and the appearance not yet settled. The revert's write is the last one
        // this test causes, so the count is read once the state has landed.
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)

        let writes = Tally()
        h.coordinator.onPresentationChange = { writes.count += 1 }
        h.clock.advance(delay: revert)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        h.coordinator.onPresentationChange = nil
        #expect(writes.count == 1)
    }

    @Test func anEventUnderTheHUDOwesTheLingerItOwesWithoutOne() async {
        // A paused switch to another track is no reason to surface, but it still
        // replaces what an invoked player shows, and with it the invoked tail —
        // exactly as it does with no HUD up.
        let h = CoordinatorHarness()
        await tucked(h)
        h.coordinator.invoke()
        await h.clock.waitForSleep(delay: Coordinator.defaultInvokedLinger)
        await hudUp(h)

        let paused = CoordinatorHarness.playingTrack(title: "Time", isPlaying: false)
        h.nowPlayingSource.emit(paused)
        #expect(await eventually { h.coordinator.layers.nowPlaying?.track == paused })

        h.clock.advance(delay: revert)
        #expect(await eventually { h.coordinator.state == .nowPlaying(paused, expanded: false) })
        await h.clock.waitForSleep(delay: linger)
        #expect(h.clock.delays == [linger, Coordinator.defaultInvokedLinger, revert, linger])
    }

    @Test func aPointerOnTheAppearanceAloneNeverHoldsTheHUD() async {
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)

        h.coordinator.hover(true, on: .nowPlaying)
        // The hover reaches the appearance it is on, HUD or not.
        #expect(h.coordinator.layers.nowPlaying == .init(track: track, expanded: true))

        h.clock.advance(delay: revert)
        #expect(await eventually { h.coordinator.layers.hud == nil })
        // The pointer still rests on the appearance: expanded, and nothing tucks it.
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))
        #expect(await eventually { h.clock.pendingSleeps == 0 })
    }

    @Test func aPointerOnTheHUDAloneHoldsTheHUDAndNothingElse() async {
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)

        h.coordinator.hover(true, on: .hud)
        #expect(h.clock.pendingSleeps == 0)   // arrival cancels the revert
        #expect(h.coordinator.layers.nowPlaying == .init(track: track, expanded: false))

        h.coordinator.hover(false, on: .hud)  // exit restarts the full delay
        await h.clock.waitForSleep(delay: revert)
        h.clock.advance(delay: revert)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
        // No hover was ever committed on the appearance, so its tuck runs.
        await h.clock.waitForSleep(delay: linger)
        h.clock.advance(delay: linger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func anEntryAheadOfTheOtherSurfacesExitStillHolds() async {
        // Two panels report on their own: the cursor crossing from the appearance
        // to the HUD can arrive on the HUD before it has left the appearance.
        let h = CoordinatorHarness()
        await appeared(h)
        await hudUp(h)

        h.coordinator.hover(true, on: .nowPlaying)
        h.coordinator.hover(true, on: .hud)
        h.coordinator.hover(false, on: .nowPlaying)

        #expect(h.coordinator.pointerInside)
        #expect(h.clock.pendingSleeps == 0)   // the HUD is held
        #expect(h.coordinator.layers.nowPlaying == .init(track: track, expanded: false))
    }

    @Test func aSurfaceWithNothingOnItIgnoresThePointer() async {
        let h = CoordinatorHarness()
        h.coordinator.hover(true, on: .hud)
        #expect(!h.coordinator.pointerInside)

        // The HUD is up, but the surface drawing the appearance alone is empty.
        await hudUp(h)
        h.coordinator.hover(true, on: .nowPlaying)
        #expect(!h.coordinator.pointerInside)
        #expect(h.clock.pendingSleeps == 1)   // the revert still runs
    }

    @Test func anAppearanceThatLeavesUnderTheHUDTakesItsHoverWithIt() async {
        // Ordering a surface out reports no exit: the hover on an appearance the
        // media's end took down must not expand the next one with no pointer on it.
        let h = CoordinatorHarness()
        await appeared(h)
        h.coordinator.hover(true, on: .nowPlaying)
        await hudUp(h)

        h.coordinator.activeNowPlayingSourceEnded()
        #expect(h.coordinator.layers == PresentationLayers(hud: hud))
        #expect(!h.coordinator.pointerInside)

        let next = CoordinatorHarness.playingTrack(title: "Time")
        h.nowPlayingSource.emit(next)
        #expect(await eventually { h.coordinator.layers.nowPlaying == .init(track: next, expanded: false) })
    }
}
