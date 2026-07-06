/// Actuator for screen brightness adjustments.
/// `display == nil` targets the internal display; a UUID targets an external
/// display (handled by the optional integration).
protocol ScreenBrightnessController: Sendable {
    /// Value normalized to 0...1.
    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws
}
