/// Actuator for screen brightness adjustments.
/// `display == nil` targets the internal display; a UUID targets an external
/// display (handled by the optional integration).
protocol ScreenBrightnessController: Sendable {
    /// Value normalized to 0...1. Returns the value actually PUT ON THE WIRE, which
    /// is not always the argument: an actuator that coalesces a drag keeps writing
    /// while newer values arrive, so the call that drove the write returns holding an
    /// argument several frames behind the finger. The echo is built from the return
    /// value for that reason — echoing the argument is what made a fast drag flick
    /// backwards, observed on hardware
    /// (docs/DECISIONS.md: betterdisplay-osd-source).
    @discardableResult
    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double
}
