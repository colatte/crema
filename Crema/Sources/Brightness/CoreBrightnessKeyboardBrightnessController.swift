/// Real actuator for the built-in keyboard backlight.
struct CoreBrightnessKeyboardBrightnessController: KeyboardBrightnessController {
    private let backend: any BrightnessBackend

    init(backend: any BrightnessBackend = CoreBrightnessKeyboardBridge()) {
        self.backend = backend
    }

    /// Both the guard and the write hop off the concurrency pools (see
    /// `blockingCall`). The write messages the private CoreBrightness client and
    /// blocks — and so does availability, which is not the pure check it reads like:
    /// this backend answers it by enumerating the backlight IDs over the client's
    /// connection, and it is re-asked per call precisely because that answer changes.
    /// Left outside the hop it ran on the cooperative pool (the caller races it on a
    /// detached task), which is the fixed-width pool the abandoning deadline itself
    /// sleeps on — enough blocked calls there and nothing on Swift concurrency runs
    /// again (docs/DECISIONS.md: async-signature-is-not-a-suspension-point).
    func setBrightness(_ value: Double) async throws {
        let level = BrightnessConversion.denormalize(value)
        try await blockingCall { [backend] in
            guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
            guard backend.write(level) else { throw BrightnessCommandError.writeFailed }
        }
    }
}
