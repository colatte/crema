/// Real actuator for the built-in keyboard backlight.
struct CoreBrightnessKeyboardBrightnessController: KeyboardBrightnessController {
    private let backend: any KeyboardBrightnessBackend

    init(backend: any KeyboardBrightnessBackend = CoreBrightnessKeyboardBridge()) {
        self.backend = backend
    }

    func setBrightness(_ value: Double) async throws {
        guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
        guard backend.write(BrightnessConversion.denormalize(value)) else {
            throw BrightnessCommandError.writeFailed
        }
    }
}
