/// Border seam for a brightness channel — one shape for both the internal
/// display and the built-in keyboard backlight. The real implementations
/// resolve private API (DisplayServicesBridge: dlopen/dlsym symbols;
/// CoreBrightnessKeyboardBridge: the private ObjC class plus the enumerated
/// built-in keyboard ID); a fake drives tests. This is what makes
/// "resolved → available / missing → degrade" unit-testable without touching
/// the real private API.
protocol BrightnessBackend: Sendable {
    /// True only when the private API resolved (symbols for the screen; class
    /// and built-in keyboard ID for the backlight).
    var isAvailable: Bool { get }
    /// Current raw level (0...1), or nil if unreadable.
    func read() -> Float?
    /// Sets the level; returns whether it took.
    func write(_ value: Float) -> Bool
}
