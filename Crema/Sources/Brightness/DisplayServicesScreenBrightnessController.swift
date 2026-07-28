/// Real actuator for the internal display's brightness. External displays are
/// the optional integration's job, never DDC here — the `on display:`
/// signature is preserved but a non-nil display is rejected.
struct DisplayServicesScreenBrightnessController: ScreenBrightnessController {
    private let backend: any BrightnessBackend

    init(backend: any BrightnessBackend = DisplayServicesBridge()) {
        self.backend = backend
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws {
        guard display == nil else { throw BrightnessCommandError.externalDisplayUnsupported }
        guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
        guard backend.write(BrightnessConversion.denormalize(value)) else {
            throw BrightnessCommandError.writeFailed
        }
    }
}
