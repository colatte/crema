import Testing
@testable import Crema

/// The real system-volume actuator's routing guard. External-display volume is
/// the optional integration's job — never DDC here — so a non-nil display is
/// rejected before any Core Audio call. Pins the never-DDC invariant; the
/// display-nil path touches the real system and is manual-smoke.
///
/// Both tests name the exact case rather than the error type: VolumeCommandError
/// also has `.noOutputDevice`, which the fall-through would throw on a
/// device-less CI if the guard regressed — a bare `throws: VolumeCommandError.self`
/// would stay green while the invariant broke.
struct CoreAudioVolumeControllerTests {

    private let external = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    @Test func setVolumeRejectsAnExternalDisplay() async {
        await #expect(throws: VolumeCommandError.externalDisplayUnsupported) {
            try await CoreAudioVolumeController().setVolume(0.5, on: external)
        }
    }

    @Test func setMutedRejectsAnExternalDisplay() async {
        await #expect(throws: VolumeCommandError.externalDisplayUnsupported) {
            try await CoreAudioVolumeController().setMuted(true, on: external)
        }
    }
}
