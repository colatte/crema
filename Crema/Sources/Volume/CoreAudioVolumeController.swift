import CoreAudio

/// Real actuator for the system output volume (default output device).
/// External displays are deliberately not handled here — no DDC anywhere in
/// this app; display-specific volume belongs to the optional integration.
/// Receiving a non-nil display is a routing error and throws.
struct CoreAudioVolumeController: VolumeController {
    enum CommandError: Error {
        case externalDisplayUnsupported
        case noOutputDevice
    }

    func setVolume(_ value: Double, on display: DisplayUUID?) async throws {
        try CoreAudioSystemOutput.writeVolume(
            VolumeConversion.denormalize(value),
            to: systemOutputDevice(for: display)
        )
    }

    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws {
        try CoreAudioSystemOutput.writeMute(muted, to: systemOutputDevice(for: display))
    }

    private func systemOutputDevice(for display: DisplayUUID?) throws -> AudioDeviceID {
        guard display == nil else { throw CommandError.externalDisplayUnsupported }
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else {
            throw CommandError.noOutputDevice
        }
        return device
    }
}
