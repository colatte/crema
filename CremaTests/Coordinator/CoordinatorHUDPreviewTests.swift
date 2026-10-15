import Testing
@testable import Crema

/// The Card placement preview: the real volume HUD, at the output's level read
/// at that moment, scoped to the displays it is asked for, reverting on the HUD's
/// own timer — and never a write to the output
/// (docs/DECISIONS.md: card-hud-placement).
@MainActor
struct CoordinatorHUDPreviewTests {

    private let cards: Set<DisplayUUID> = [DisplayUUID(rawValue: "CARD")]

    @Test func showsTheLevelReadOnTheNamedDisplaysAndRevertsOnTheHUDTimer() async {
        let h = CoordinatorHarness()
        let level = SystemHUD(kind: .volume, value: 0.35, isMuted: true)
        h.volumeReading.reading = level

        h.coordinator.previewHUD(on: cards)

        #expect(await eventually { h.coordinator.state == .hud(level) })
        #expect(h.coordinator.layers.hudDisplays == cards)
        await h.clock.waitForSleep()
        #expect(h.clock.delays.last == Coordinator.defaultHUDRevertDelay)

        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .hidden })
        #expect(h.coordinator.layers.hudDisplays == nil)
        // A read, never a write: the preview must not move the output it shows.
        #expect(h.volume.commands.isEmpty)
        #expect(h.volumeReading.reads == 1)
    }

    @Test func revertsToTheAppearanceItRoseOver() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.coordinator.previewHUD(on: cards)
        #expect(await eventually {
            if case .hud = h.coordinator.state { return true } else { return false }
        })
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func noDisplaysToShowItOnReadsNothingAndShowsNothing() {
        // Synchronous refusal: with no display drawing Card there is nothing to
        // preview, so not even the read is scheduled.
        let h = CoordinatorHarness()

        h.coordinator.previewHUD(on: [])

        #expect(h.volumeReading.reads == 0)
        #expect(h.coordinator.state == .hidden)
    }

    @Test func aFailedReadShowsNothing() async {
        let h = CoordinatorHarness()
        h.volumeReading.reading = nil

        h.coordinator.previewHUD(on: cards)

        #expect(await eventually { h.volumeReading.reads == 1 })
        #expect(await !footprintAppears { h.coordinator.state != .hidden })
    }

    @Test func aReportedHUDLandingDuringTheReadWinsAndIsNotScoped() async {
        // The read is the slow part. A key pressed meanwhile is newer than the
        // level being read, so the late reading is dropped rather than drawn over
        // it — and the reported bar keeps its own scope, its target's.
        let h = CoordinatorHarness()
        h.volumeReading.held = true
        h.coordinator.previewHUD(on: cards)
        #expect(await eventually { h.volumeReading.reads == 1 })

        let pressed = SystemHUD(kind: .volume, value: 0.8)
        h.hudSource.emit(pressed)
        #expect(await eventually { h.coordinator.state == .hud(pressed) })
        h.volumeReading.held = false

        #expect(await !footprintAppears { h.coordinator.state != .hud(pressed) })
        #expect(h.coordinator.layers.hudDisplays == nil)
    }

    @Test func aReportedHUDOverThePreviewIsDrawnWhereverItsTargetPutsIt() async {
        // A drag on the preview's bar is the person's own: its echo comes back as
        // a reported HUD and is no longer the preview.
        let h = CoordinatorHarness()
        h.coordinator.previewHUD(on: cards)
        #expect(await eventually { h.coordinator.layers.hudDisplays == cards })

        let echo = SystemHUD(kind: .volume, value: 0.6)
        h.hudSource.emit(echo)

        #expect(await eventually { h.coordinator.state == .hud(echo) })
        #expect(h.coordinator.layers.hudDisplays == nil)
    }
}
