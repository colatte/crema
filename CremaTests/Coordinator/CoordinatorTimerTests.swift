import Testing
@testable import Crema

/// HUD revert timers driven by an injectable clock; tests never sleep.
@MainActor
struct CoordinatorTimerTests {

    @Test func hudRevertsToNowPlayingAfterDelay() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        await h.clock.waitForSleep()
        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func hudRevertsToHiddenWithoutMedia() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.2))
        #expect(await eventually { h.coordinator.state != .hidden })

        await h.clock.waitForSleep()
        h.clock.advance()

        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func newHUDEventRestartsTheTimer() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.3))
        await h.clock.waitForSleep()

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.4))

        // The first timer must be cancelled and a fresh one parked.
        #expect(await eventually { h.clock.cancelledCount == 1 })
        await h.clock.waitForSleep()
        #expect(h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.4)))

        h.clock.advance()
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func anIdenticalBoundaryHUDStillRestartsTheTimer() async {
        // S3: at a scale boundary a consumed key re-emits the SAME-value HUD (the
        // brightness gate's boundary refresh / volume's boundary re-read). Even
        // unchanged, it must restart the revert timer so a mash at the limit
        // keeps the bar up — matching native's flash on every press — instead of
        // tucking ~1.5s after the last CHANGING press.
        let h = CoordinatorHarness()
        let hud = SystemHUD(kind: .screenBrightness, value: 1)
        h.hudSource.emit(hud)
        #expect(await eventually { h.coordinator.state == .hud(hud) })
        await h.clock.waitForSleep()   // first revert timer parked

        h.hudSource.emit(hud)          // identical boundary refresh

        #expect(await eventually { h.clock.cancelledCount == 1 })
        await h.clock.waitForSleep()   // a fresh timer is parked, HUD held
        #expect(h.coordinator.state == .hud(hud))
    }

    @Test func usesTheDefaultDelayFromASinglePlace() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        await h.clock.waitForSleep()

        #expect(Coordinator.defaultHUDRevertDelay == 1.5)
        #expect(h.clock.delays == [Coordinator.defaultHUDRevertDelay])
    }

    @Test func delayIsConfigurable() async {
        let h = CoordinatorHarness(hudRevertDelay: 0.25)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        await h.clock.waitForSleep()

        #expect(h.clock.delays == [0.25])
    }

    @Test func revertAfterPointerExitRestoresTheHeldNowPlayingExpanded() async {
        // With the hold (docs/DECISIONS.md: hud-capsule-track) the revert can
        // no longer fire while the pointer rests on the HUD — it restarts on
        // pointer exit. Entering through the intent path keeps `isHovering`
        // committed while the exit debounce is pending, so a revert firing in
        // that window still restores the now-playing EXPANDED — the corner the
        // old always-armed revert pinned directly.
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.hoverIntent(true)
        await h.clock.waitForSleep(delay: Coordinator.defaultHoverIntentDelay)
        h.clock.advance(delay: Coordinator.defaultHoverIntentDelay)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: true) })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })
        // Held: the pointer is inside, so no revert timer is parked.
        #expect(h.clock.pendingSleeps == 0)

        h.coordinator.hoverIntent(false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: true) })
    }
}
