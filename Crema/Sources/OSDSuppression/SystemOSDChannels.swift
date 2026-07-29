/// The three real channels, grouped: each is a thin border adapter pairing a
/// actuator (writes) with its matching border read — no logic beyond
/// normalization, so everything interesting stays in the testable suppressor.

/// Volume: Core Audio reads + the injected controller for writes.
struct CoreAudioOSDVolumeChannel: OSDVolumeChannel {
    let controller: any VolumeController

    func isAvailable() -> Bool {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return false }
        return CoreAudioSystemOutput.supportsVolume(device)
    }

    func supportsMute() -> Bool {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return false }
        return CoreAudioSystemOutput.supportsMute(device)
    }

    func read() -> Double? {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID(),
              let raw = CoreAudioSystemOutput.readVolume(device)
        else { return nil }
        return VolumeConversion.normalize(raw)
    }

    func apply(_ value: Double) async throws {
        try await controller.setVolume(value, on: nil)
    }

    func readMuted() -> Bool? {
        guard let device = CoreAudioSystemOutput.defaultOutputDeviceID() else { return nil }
        return CoreAudioSystemOutput.readMute(device)
    }

    func setMuted(_ muted: Bool) async throws {
        try await controller.setMuted(muted, on: nil)
    }
}

/// Internal-display brightness: the DisplayServices backend for reads, the
/// injected controller for writes.
struct ScreenBrightnessOSDChannel: OSDChannel {
    let backend: any BrightnessBackend
    let controller: any ScreenBrightnessController

    func isAvailable() -> Bool {
        backend.isAvailable
    }

    func read() -> Double? {
        backend.read().map { BrightnessConversion.normalize($0) }
    }

    func apply(_ value: Double) async throws {
        try await controller.setBrightness(value, on: nil)
    }
}

/// Built-in keyboard backlight: the CoreBrightness backend for reads, the
/// injected controller for writes.
struct KeyboardBrightnessOSDChannel: OSDChannel {
    let backend: any BrightnessBackend
    let controller: any KeyboardBrightnessController

    func isAvailable() -> Bool {
        backend.isAvailable
    }

    func read() -> Double? {
        backend.read().map { BrightnessConversion.normalize($0) }
    }

    func apply(_ value: Double) async throws {
        try await controller.setBrightness(value)
    }
}
