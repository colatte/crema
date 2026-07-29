import CoreAudio

/// Real actuator for the system output volume (default output device).
/// External displays are deliberately not handled here — no DDC anywhere in
/// this app; display-specific volume belongs to the optional integration.
/// Receiving a non-nil display is a routing error and throws.
struct CoreAudioVolumeController: VolumeController {
    func setVolume(_ value: Double, on display: DisplayUUID?) async throws {
        try await write(on: display) { device in
            try CoreAudioSystemOutput.writeVolume(VolumeConversion.denormalize(value), to: device)
        }
    }

    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws {
        try await write(on: display) { device in
            try CoreAudioSystemOutput.writeMute(muted, to: device)
        }
    }

    /// The device lookup and the write are both blocking Core Audio IPC, so the
    /// pair hops off the concurrency pools together — see `blockingCall` for why
    /// a blocking call must never hold a cooperative-pool thread. Resolving the
    /// device inside the same hop also keeps a write from addressing a device
    /// that was replaced between the lookup and the write; an output handoff
    /// mid-keypress is exactly when that gap is widest.
    private func write(
        on display: DisplayUUID?,
        _ body: @escaping @Sendable (AudioDeviceID) throws -> Void
    ) async throws {
        guard display == nil else { throw VolumeCommandError.externalDisplayUnsupported }
        try await blockingCall {
            guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else {
                throw VolumeCommandError.noOutputDevice
            }
            try body(device)
        }
    }
}
