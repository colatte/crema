/// Real actuator for the internal display's brightness. External displays are
/// the optional integration's job, never DDC here — the `on display:`
/// signature is preserved but a non-nil display is rejected.
struct DisplayServicesScreenBrightnessController: ScreenBrightnessController {
    private let backend: any BrightnessBackend
    /// Which UUID names this controller's own screen. Injected for the same reason
    /// the backend is: resolving it means enumerating displays, and a unit test
    /// never touches real system API.
    private let builtInDisplay: @Sendable () -> DisplayUUID?

    init(
        backend: any BrightnessBackend = DisplayServicesBridge(),
        builtInDisplay: @escaping @Sendable () -> DisplayUUID? = { ScreenTranslation.builtInDisplayUUID() }
    ) {
        self.backend = backend
        self.builtInDisplay = builtInDisplay
    }

    /// The routing and availability guards are pure and stay here; the write is
    /// a blocking dlsym'd C call, so it hops off the concurrency pools (see
    /// `blockingCall`).
    ///
    /// Accepts nil OR the built-in panel's own UUID, because those name the same
    /// screen. Refusing a non-nil display outright looked right while nil was the
    /// only way to say "the built-in" — then the neighbour integration started
    /// naming displays explicitly, and this guard would have thrown
    /// `externalDisplayUnsupported` for the built-in panel, silently swallowing a
    /// drag on its own bar. Anything else is genuinely an external display, which
    /// belongs to the optional integration and never to DisplayServices.
    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        if let display, display != builtInDisplay() {
            throw BrightnessCommandError.externalDisplayUnsupported
        }
        guard backend.isAvailable else { throw BrightnessCommandError.unavailable }
        let level = BrightnessConversion.denormalize(value)
        try await blockingCall { [backend] in
            guard backend.write(level) else { throw BrightnessCommandError.writeFailed }
        }
        // Nothing coalesces here: what was asked is what went out.
        return value
    }
}
