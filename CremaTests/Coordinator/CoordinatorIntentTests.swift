import Testing
@testable import Crema

/// View intents: views only report; the Coordinator routes to actuators.
@MainActor
struct CoordinatorIntentTests {

    @Test func hoverExpandsAndCollapsesNowPlaying() async {
        let h = CoordinatorHarness()
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        h.coordinator.hover(true)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: true))

        h.coordinator.hover(false)
        #expect(h.coordinator.state == .nowPlaying(track, expanded: false))
    }

    @Test func hoverBeforeMediaLeavesNoResidueAndTheNextTrackAppearsCompact() async {
        let h = CoordinatorHarness()
        // Hover over an empty region is a no-op — no dwell, no remembered
        // commitment. (In the real app the monitor isn't even armed while
        // hidden; a pointer already sitting on a fresh appearance re-enters
        // through the monitor's arming sample, not through memory here.)
        h.coordinator.hover(true)
        await settle()
        #expect(h.coordinator.state == .hidden)

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)

        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })
    }

    @Test func playPauseIntentReachesTheMediaActuator() async {
        let h = CoordinatorHarness()

        h.coordinator.togglePlayPause()

        #expect(await eventually { h.media.commands == [.togglePlayPause] })
    }

    @Test func skipIntentsReachTheMediaActuator() async {
        let h = CoordinatorHarness()

        h.coordinator.nextTrack()
        #expect(await eventually { h.media.commands == [.nextTrack] })

        h.coordinator.previousTrack()
        #expect(await eventually { h.media.commands == [.nextTrack, .previousTrack] })
    }

    @Test func scrubIntentReachesTheMediaActuator() async {
        let h = CoordinatorHarness()

        h.coordinator.scrub(to: 42)

        #expect(await eventually { h.media.commands == [.seek(seconds: 42)] })
    }

    @Test func volumeHUDSliderRoutesToTheVolumeActuator() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.7)

        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
        #expect(h.screen.commands.isEmpty)
        #expect(h.keyboard.commands.isEmpty)
    }

    /// Parity pin (audit §A3): a muted device dragged to an audible target
    /// unmutes before the volume write, in that order — the same sequence the
    /// volume-up key produces, so a drag never raises the number onto silence.
    @Test func mutedVolumeSliderDraggedUpUnmutesBeforeSettingVolume() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.0, isMuted: true))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.0, isMuted: true)) })

        h.coordinator.hudSliderChanged(to: 0.3)

        #expect(await eventually {
            h.volume.commands == [.setMuted(false, display: nil), .setVolume(0.3, display: nil)]
        })
        #expect(h.screen.commands.isEmpty)
        #expect(h.keyboard.commands.isEmpty)
    }

    /// A drag to exactly 0 leaves mute untouched — parity with volume-down,
    /// which never unmutes.
    @Test func mutedVolumeSliderDraggedToZeroLeavesMuteUntouched() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.2, isMuted: true))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.2, isMuted: true)) })

        h.coordinator.hudSliderChanged(to: 0.0)

        #expect(await eventually { h.volume.commands == [.setVolume(0.0, display: nil)] })
    }

    /// An unmuted device never gets a spurious unmute — the write path stays a
    /// single setVolume.
    @Test func unmutedVolumeSliderOnlySetsVolume() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5, isMuted: false))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5, isMuted: false)) })

        h.coordinator.hudSliderChanged(to: 0.7)

        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
    }

    /// The unmute is scoped to the volume channel: brightness drags never touch
    /// the volume actuator, muted-flag on the HUD or not.
    @Test func brightnessSlidersNeverTouchMute() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5, isMuted: true))
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.hudSliderChanged(to: 0.8)
        #expect(await eventually { h.screen.commands == [.setBrightness(0.8, display: nil)] })

        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.5, isMuted: true))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .keyboardBrightness, value: 0.5, isMuted: true)) })
        h.coordinator.hudSliderChanged(to: 0.1)
        #expect(await eventually { h.keyboard.commands == [.setBrightness(0.1)] })

        #expect(h.volume.commands.isEmpty)
    }

    @Test func brightnessHUDSliderRoutesToTheRightActuatorAndDisplay() async {
        let h = CoordinatorHarness()
        let external = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5, display: external))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)

        #expect(await eventually { h.screen.commands == [.setBrightness(0.8, display: external)] })
        #expect(h.volume.commands.isEmpty)
    }

    @Test func keyboardHUDSliderRoutesToTheKeyboardActuator() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .keyboardBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.1)

        #expect(await eventually { h.keyboard.commands == [.setBrightness(0.1)] })
    }

    @Test func hudSliderWithoutAVisibleHUDRoutesNowhere() async {
        let h = CoordinatorHarness()

        h.coordinator.hudSliderChanged(to: 0.9)
        await settle()

        #expect(h.volume.commands.isEmpty)
        #expect(h.screen.commands.isEmpty)
        #expect(h.keyboard.commands.isEmpty)
    }
}
