import Testing
@testable import Crema

/// Controller logic over fake backends: writes are clamped, an
/// unavailable backend and an external display both throw (no DDC).
struct BrightnessControllerTests {

    private let external = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")

    // MARK: - Screen

    @Test func screenControllerWritesClampedValueToInternalDisplay() async throws {
        let backend = FakeScreenBrightnessBackend(available: true)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        try await controller.setBrightness(0.3, on: nil)
        try await controller.setBrightness(1.5, on: nil)

        #expect(backend.writes == [BrightnessConversion.denormalize(0.3), 1.0])
    }

    @Test func screenControllerRejectsExternalDisplay() async {
        let backend = FakeScreenBrightnessBackend(available: true)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5, on: external)
        }
        #expect(backend.writes.isEmpty)
    }

    @Test func screenControllerThrowsWhenBackendUnavailable() async {
        let backend = FakeScreenBrightnessBackend(available: false)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5, on: nil)
        }
    }

    // MARK: - Keyboard

    @Test func keyboardControllerWritesClampedValue() async throws {
        let backend = FakeKeyboardBrightnessBackend(available: true)
        let controller = CoreBrightnessKeyboardBrightnessController(backend: backend)

        try await controller.setBrightness(0.5)
        try await controller.setBrightness(-0.2)

        #expect(backend.writes == [0.5, 0.0])
    }

    @Test func keyboardControllerThrowsWhenBackendUnavailable() async {
        let backend = FakeKeyboardBrightnessBackend(available: false)
        let controller = CoreBrightnessKeyboardBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5)
        }
    }
}
