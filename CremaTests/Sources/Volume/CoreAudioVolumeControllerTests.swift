import Testing
@testable import Crema

/// The real system-volume actuator's routing guard. External-display volume is
/// the optional integration's job — never DDC here — so a non-nil display is
/// rejected before any Core Audio call. Pins the never-DDC invariant; the
/// display-nil path touches the real system and is manual-smoke.
///
/// The exact case matters: VolumeCommandError also has `.noOutputDevice`, which
/// the fall-through would throw on a device-less CI if the guard regressed — a
/// bare `throws: VolumeCommandError.self` would stay green while the invariant
/// broke.
struct CoreAudioVolumeControllerTests {

    private let external = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    @Test func setVolumeRejectsAnExternalDisplay() async {
        do {
            try await CoreAudioVolumeController().setVolume(0.5, on: external)
            Issue.record("expected an external display to be rejected before any Core Audio call")
        } catch VolumeCommandError.externalDisplayUnsupported {
            // expected
        } catch {
            Issue.record("threw the wrong error: \(error)")
        }
    }

    @Test func setMutedRejectsAnExternalDisplay() async {
        do {
            try await CoreAudioVolumeController().setMuted(true, on: external)
            Issue.record("expected an external display to be rejected before any Core Audio call")
        } catch VolumeCommandError.externalDisplayUnsupported {
            // expected
        } catch {
            Issue.record("threw the wrong error: \(error)")
        }
    }
}
