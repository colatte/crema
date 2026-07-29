/// Real actuator for the built-in keyboard backlight.
struct CoreBrightnessKeyboardBrightnessController: KeyboardBrightnessController {
    private let backend: any BrightnessBackend

    init(backend: any BrightnessBackend = CoreBrightnessKeyboardBridge()) {
        self.backend = backend
    }

    /// The availability guard is pure and stays here; the write messages the
    /// private CoreBrightness client and blocks, so it hops off the concurrency
    /// pools (see `blockingCall`).
    func setBrightness(_ value: Double) async throws {
        guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
        let level = BrightnessConversion.denormalize(value)
        try await blockingCall { [backend] in
            guard backend.write(level) else { throw BrightnessCommandError.writeFailed }
        }
    }
}
