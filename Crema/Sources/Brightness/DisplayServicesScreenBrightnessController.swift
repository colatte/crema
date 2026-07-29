/// Real actuator for the internal display's brightness. External displays are
/// the optional integration's job, never DDC here — the `on display:`
/// signature is preserved but a non-nil display is rejected.
struct DisplayServicesScreenBrightnessController: ScreenBrightnessController {
    private let backend: any BrightnessBackend

    init(backend: any BrightnessBackend = DisplayServicesBridge()) {
        self.backend = backend
    }

    /// The routing and availability guards are pure and stay here; the write is
    /// a blocking dlsym'd C call, so it hops off the concurrency pools (see
    /// `blockingCall`).
    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws {
        guard display == nil else { throw BrightnessCommandError.externalDisplayUnsupported }
        guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
        let level = BrightnessConversion.denormalize(value)
        try await blockingCall { [backend] in
            guard backend.write(level) else { throw BrightnessCommandError.writeFailed }
        }
    }
}
