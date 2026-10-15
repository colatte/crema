import Testing
@testable import Crema

/// The raw pointer (`pointerInside`) — the global signal the timers key on:
/// it must flip on BOTH hover paths (the debounced intent edge
/// before its delay, and the immediate commit the Card/Classic panels use),
/// and the pointer must hold a visible HUD (cancel the revert on arrival,
/// restart the full delay on exit). The per-display knob reads the panel-local
/// SurfaceDisplayPolicy.pointerInside, set at the panel's dispatch.
@MainActor
struct CoordinatorPointerSignalTests {

    @Test func pointerMirrorFlipsOnTheIntentEdgeWithoutTheDelay() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        _ = await eventually {
            if case .hud = h.coordinator.state { return true } else { return false }
        }

        #expect(!h.coordinator.pointerInside)
        h.coordinator.hoverIntent(true)
        #expect(h.coordinator.pointerInside)   // no clock advance: raw signal, not committed hover
        h.coordinator.hoverIntent(false)
        #expect(!h.coordinator.pointerInside)
    }

    @Test func pointerMirrorAlsoFlipsOnTheImmediatePath() async {
        // The path the Card/Classic panels dispatch through; without the flip
        // the knob can never appear.
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        _ = await eventually {
            if case .hud = h.coordinator.state { return true } else { return false }
        }

        h.coordinator.hover(true, on: .both)
        #expect(h.coordinator.pointerInside)
        h.coordinator.hover(false, on: .both)
        #expect(!h.coordinator.pointerInside)
    }

    @Test func hoverExitBuysTheShortRelingerNotAFullOne() async {
        // Calibration in test: a graze must not re-arm the full 3 s linger
        // — the exit buys hoverExitRelinger (1.5 s) before the tuck.
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        _ = await eventually { h.coordinator.state != .hidden }

        h.coordinator.hover(true, on: .both)
        h.coordinator.hover(false, on: .both)
        await h.clock.waitForSleep(delay: Coordinator.hoverExitRelinger)
        #expect(h.clock.delays.last == Coordinator.hoverExitRelinger)
        h.clock.advance(delay: Coordinator.hoverExitRelinger)
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func pointerHoldsTheHUDAndExitRestartsTheRevert() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        _ = await eventually {
            if case .hud = h.coordinator.state { return true } else { return false }
        }
        await h.clock.waitForSleep()          // the revert timer is parked

        h.coordinator.hover(true, on: .both)  // arrival cancels the revert
        #expect(h.clock.pendingSleeps == 0)

        h.coordinator.hover(false, on: .both) // exit restarts the full delay
        await h.clock.waitForSleep()
        h.clock.advance()
        #expect(await eventually { h.coordinator.state == .hidden })
    }

    @Test func aHUDRisingUnderAStillPointerRevertsOnItsTimer() async {
        // The production order: the HUD's state write runs the frame pass, which
        // arms the notch's monitor, whose arming sample finds the resting cursor
        // inside and reports it — all inside the write, before `publishHUD`
        // decides whether to start the revert. Nobody moved the mouse, so nothing
        // holds the HUD (docs/DECISIONS.md: hud-capsule-track).
        let h = CoordinatorHarness()
        var sampled = false
        h.coordinator.onPresentationChange = { [coordinator = h.coordinator] in
            guard !sampled, case .hud = coordinator.state else { return }
            sampled = true
            coordinator.hoverIntent(true, byMovement: false)
        }

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.layers.hud == nil })
        #expect(sampled)
    }

    @Test func aMouseEventOnAStillPointerTakesTheHold() async {
        // The pointer the arming sample found is the user's the moment it moves:
        // from then on it holds the HUD like any arrival, and its exit restarts
        // the full delay.
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.layers.hud != nil })
        h.coordinator.hover(true, on: .both, byMovement: false)
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)

        h.coordinator.hover(true, on: .both, byMovement: true)
        #expect(h.clock.pendingSleeps == 0)

        h.coordinator.hover(false, on: .both)
        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.layers.hud == nil })
    }
}
