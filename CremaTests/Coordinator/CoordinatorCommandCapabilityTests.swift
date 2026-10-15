import Testing
@testable import Crema

/// Commands degrade honestly: a media-command failure (blocked write
/// path) flips `commandsAvailable`; success restores it; HUD commands don't
/// touch it. All with mocks, no real process.
///
/// A command's verdict lands on the main actor after an await on the
/// nonisolated double, and nothing signals that it has: a denial waits for the
/// command to reach the double, then gives the hop back a wall-clock window
/// (`footprintAppears`) — a drain of the main actor never sees the hop coming.
@MainActor
struct CoordinatorCommandCapabilityTests {

    @Test func commandsAvailableStartsOptimistic() {
        #expect(CoordinatorHarness().coordinator.commandsAvailable)
        #expect(CoordinatorHarness().coordinator.skipCommandsAvailable)
        #expect(CoordinatorHarness().coordinator.skipControlsEnabled)
    }

    @Test func aFailedSkipDegradesOnlyTheSkipControls() async {
        // A source can accept play/pause but reject track skipping: the
        // broken control grays out, the working one stays live.
        let h = CoordinatorHarness()
        h.media.shouldThrow = true

        h.coordinator.nextTrack()

        #expect(await eventually { !h.coordinator.skipControlsEnabled })
        #expect(h.coordinator.commandsAvailable)
    }

    @Test func aFailedPlayPauseDisablesTheSkipsToo() async {
        // The general write path being down takes everything with it —
        // skipControlsEnabled composes both flags.
        let h = CoordinatorHarness()
        h.media.shouldThrow = true

        h.coordinator.togglePlayPause()

        #expect(await eventually { !h.coordinator.commandsAvailable })
        #expect(!h.coordinator.skipControlsEnabled)
        #expect(h.coordinator.skipCommandsAvailable)   // the skip-specific path was never blamed
    }

    @Test func skipRecoversOnSuccessAndOnANewTrack() async {
        let h = CoordinatorHarness()
        h.media.shouldThrow = true
        h.coordinator.previousTrack()
        #expect(await eventually { !h.coordinator.skipCommandsAvailable })

        // A succeeding skip restores the flag.
        h.media.shouldThrow = false
        h.coordinator.nextTrack()
        #expect(await eventually { h.coordinator.skipCommandsAvailable })

        // And so does a surfacing media event (the natural re-check point).
        h.media.shouldThrow = true
        h.coordinator.nextTrack()
        #expect(await eventually { !h.coordinator.skipCommandsAvailable })
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Time"))
        #expect(await eventually { h.coordinator.skipCommandsAvailable })
    }

    @Test func mediaThatProhibitsSkippingDisablesTheSkipsWithoutBlamingThePath() async {
        // Prohibiting media (radio, live) swallows a delivered skip without an
        // error, so the failure-driven flags never see it — the metadata gates
        // the controls instead, and no command path gets blamed.
        let h = CoordinatorHarness()
        var radio = CoordinatorHarness.playingTrack(title: "Radio")
        radio.supportsSkip = false

        h.nowPlayingSource.emit(radio)

        #expect(await eventually { !h.coordinator.skipControlsEnabled })
        #expect(h.coordinator.commandsAvailable)
        #expect(h.coordinator.skipCommandsAvailable)

        // A skippable track lifts the gate again.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Song"))
        #expect(await eventually { h.coordinator.skipControlsEnabled })
    }

    @Test func aTransientNoActiveSourceDoesNotDisableSkips() async {
        let h = CoordinatorHarness()
        h.media.errorToThrow = NowPlayingCommandError.noActiveSource

        h.coordinator.nextTrack()

        #expect(await eventuallyOffActor { h.media.commands == [.nextTrack] })
        #expect(await !footprintAppears { !h.coordinator.skipCommandsAvailable })
    }

    @Test func aFailedMediaCommandMarksCommandsUnavailable() async {
        let h = CoordinatorHarness()
        h.media.shouldThrow = true

        h.coordinator.togglePlayPause()

        #expect(await eventually { !h.coordinator.commandsAvailable })
    }

    @Test func aSucceedingMediaCommandKeepsThemAvailable() async {
        let h = CoordinatorHarness()

        h.coordinator.togglePlayPause()

        #expect(await eventuallyOffActor { h.media.commands == [.togglePlayPause] })
        #expect(await !footprintAppears { !h.coordinator.commandsAvailable })
    }

    @Test func recoversWhenACommandSucceedsAgain() async {
        let h = CoordinatorHarness()
        h.media.shouldThrow = true
        h.coordinator.togglePlayPause()
        #expect(await eventually { !h.coordinator.commandsAvailable })

        h.media.shouldThrow = false
        h.coordinator.scrub(to: 10)
        #expect(await eventually { h.coordinator.commandsAvailable })
    }

    @Test func recoversWhenANewTrackStartsPlaying() async {
        let h = CoordinatorHarness()
        h.media.shouldThrow = true
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "A"))
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.togglePlayPause()
        #expect(await eventually { !h.coordinator.commandsAvailable })

        // A new track appears — the controls become usable again (the recovery
        // path the disabled UI would otherwise block).
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "B"))
        #expect(await eventually { h.coordinator.commandsAvailable })
    }

    @Test func aTransientNoActiveSourceDoesNotDisableControls() async {
        let h = CoordinatorHarness()
        h.media.errorToThrow = NowPlayingCommandError.noActiveSource

        h.coordinator.togglePlayPause()

        #expect(await eventuallyOffActor { h.media.commands == [.togglePlayPause] })
        // transient — not latched off
        #expect(await !footprintAppears { !h.coordinator.commandsAvailable })
    }

    @Test func aSurfacingEventDuringAHUDRestoresDegradedControls() async {
        // The heal reaches the event whatever the HUD is doing: a track change
        // arriving while a HUD owns the surface must re-enable the controls, or
        // play/pause stays dead for the rest of the track.
        let h = CoordinatorHarness()
        h.media.shouldThrow = true
        h.coordinator.nextTrack()
        #expect(await eventually { !h.coordinator.skipCommandsAvailable })
        h.coordinator.togglePlayPause()
        #expect(await eventually { !h.coordinator.commandsAvailable })

        // A HUD takes the surface.
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        // A surfacing media event lands DURING the HUD.
        h.media.shouldThrow = false
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Time"))

        #expect(await eventually { h.coordinator.commandsAvailable })
        #expect(await eventually { h.coordinator.skipCommandsAvailable })
        // The HUD still owns the surface: the event reached only the appearance
        // under it, which shows on the revert.
        #expect(h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)))
    }

    @Test func hudCommandFailureDoesNotDisableMediaControls() async {
        let h = CoordinatorHarness()
        h.volume.shouldThrow = true
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.7)

        #expect(await eventuallyOffActor { h.volume.commands == [.setVolume(0.7, display: nil)] })
        // unaffected by a HUD failure
        #expect(await !footprintAppears { !h.coordinator.commandsAvailable })
    }
}
