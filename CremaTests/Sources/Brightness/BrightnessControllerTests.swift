import Testing
@testable import Crema

/// Controller logic over fake backends: writes are clamped, an
/// unavailable backend and an external display both throw (no DDC).
struct BrightnessControllerTests {

    /// Unmistakably NOT the built-in. The previous fixture carried
    /// 37D8832A-2D66-02CA-B9F7-8F30A301B230 under the name `external` — copied from
    /// real hardware, where it is the BUILT-IN panel's UUID. It passed only because
    /// the controller used to reject every non-nil display, so the value never
    /// mattered; the moment the controller learned to recognise its own screen, the
    /// fixture started asserting the opposite of its name.
    private let external = DisplayUUID(rawValue: "EXTERNAL-NOT-THE-BUILT-IN")
    private let builtIn = DisplayUUID(rawValue: "THE-BUILT-IN-PANEL")

    // MARK: - Screen

    @Test func screenControllerWritesClampedValueToInternalDisplay() async throws {
        let backend = FakeBrightnessBackend(available: true)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        try await controller.setBrightness(0.3, on: nil)
        try await controller.setBrightness(1.5, on: nil)

        #expect(backend.writes == [BrightnessConversion.denormalize(0.3), 1.0])
    }

    @Test func screenControllerRejectsExternalDisplay() async {
        let backend = FakeBrightnessBackend(available: true)
        // Injected rather than resolved: reading the real built-in means
        // enumerating displays, and a unit test never touches system API.
        let controller = DisplayServicesScreenBrightnessController(
            backend: backend, builtInDisplay: { [builtIn] in builtIn }
        )

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5, on: external)
        }
        #expect(backend.writes.isEmpty)
    }

    @Test func screenControllerAcceptsItsOwnDisplayNamedExplicitly() async throws {
        // nil and the built-in's own UUID name the same screen. Rejecting every
        // non-nil display read as correct while nil was the only way to say "the
        // built-in" — then the neighbour integration began naming displays, and this
        // controller would have thrown externalDisplayUnsupported for the panel it
        // exists to drive, swallowing a drag on its own bar with only a log line.
        let backend = FakeBrightnessBackend(available: true)
        let controller = DisplayServicesScreenBrightnessController(
            backend: backend, builtInDisplay: { [builtIn] in builtIn }
        )

        try await controller.setBrightness(0.5, on: builtIn)
        try await controller.setBrightness(0.25, on: nil)

        #expect(backend.writes == [
            BrightnessConversion.denormalize(0.5),
            BrightnessConversion.denormalize(0.25),
        ])
    }

    @Test func screenControllerThrowsWhenBackendUnavailable() async {
        let backend = FakeBrightnessBackend(available: false)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5, on: nil)
        }
    }

    @Test func screenControllerSurfacesAFailureWhenTheAppliedWriteIsRejected() async {
        // Available backend whose applied write does not take. Apply-and-verify
        // must surface a failure (writeFailed, distinct from unavailable) so the
        // suppressor auto-disengages instead of silently swallowing the key.
        let backend = FakeBrightnessBackend(available: true, writeSucceeds: false)
        let controller = DisplayServicesScreenBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5, on: nil)
        }
    }

    // MARK: - Keyboard

    @Test func keyboardControllerWritesClampedValue() async throws {
        let backend = FakeBrightnessBackend(available: true)
        let controller = CoreBrightnessKeyboardBrightnessController(backend: backend)

        try await controller.setBrightness(0.5)
        try await controller.setBrightness(-0.2)

        #expect(backend.writes == [0.5, 0.0])
    }

    @Test func keyboardControllerThrowsWhenBackendUnavailable() async {
        let backend = FakeBrightnessBackend(available: false)
        let controller = CoreBrightnessKeyboardBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5)
        }
    }

    @Test func keyboardControllerSurfacesAFailureWhenTheAppliedWriteIsRejected() async {
        let backend = FakeBrightnessBackend(available: true, writeSucceeds: false)
        let controller = CoreBrightnessKeyboardBrightnessController(backend: backend)

        await #expect(throws: BrightnessCommandError.self) {
            try await controller.setBrightness(0.5)
        }
    }
}
