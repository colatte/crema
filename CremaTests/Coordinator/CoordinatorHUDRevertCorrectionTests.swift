import Testing
@testable import Crema

/// What the HUD's revert owes the bar it takes away, on BOTH of its exits. The
/// hiding exit is already pinned (CoordinatorNeighbourBrightnessTests,
/// aPendingCorrectionDoesNotOutliveTheBarItWasFor); this is the other one — the
/// revert that resumes a now-playing appearance, which for the same reasons must
/// not carry a pending correction forward into the next bar
/// (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
@MainActor
struct CoordinatorHUDRevertCorrectionTests {

    @Test func aPendingCorrectionDoesNotSurviveARevertThatResumesTheMedia() async {
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()

        // A visible appearance under the HUD is what makes the revert take the
        // resuming arm instead of hiding — the arm that, unguarded, keeps the mark.
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state == .hud(onExternalDisplay(0.5)) })
        h.coordinator.hudSliderChanged(to: 0.9)
        // The write task's end is when the decline marks the bar: a command
        // landing is still ahead of it.
        #expect(await eventually { h.finishedScreenWrites.count == 1 })   // nothing wrote: a correction is owed

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        // A new bar, on a display both actuators can write, and a release that
        // beats its answer back — the shape a stale mark ruins: it would fire
        // here and pull a perfectly good drag home to a level two readings old.
        h.external?.acceptEverything()
        h.screen.acceptEverything()
        h.hudSource.emit(neighbourHUD(0.3))
        #expect(await eventually { h.coordinator.state == .hud(neighbourHUD(0.3)) })
        h.coordinator.hudSliderChanged(to: 0.8)
        h.coordinator.hudSliderReleased()
        #expect(await eventually { h.finishedScreenWrites.count == 2 })

        #expect(h.coordinator.state == .hud(neighbourHUD(0.8)))   // never yanked to 0.5
    }
}
