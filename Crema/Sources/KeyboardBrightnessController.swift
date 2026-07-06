/// Actuator for keyboard backlight adjustments (always the built-in keyboard).
protocol KeyboardBrightnessController: Sendable {
    /// Value normalized to 0...1.
    func setBrightness(_ value: Double) async throws
}
