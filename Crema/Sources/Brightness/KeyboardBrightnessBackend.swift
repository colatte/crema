/// Border seam for the built-in keyboard's backlight. The real implementation
/// (CoreBrightnessKeyboardBridge) resolves the private ObjC class and enumerates
/// the built-in keyboard ID; a fake drives tests.
protocol KeyboardBrightnessBackend: Sendable {
    /// True only when the private class resolved and a built-in keyboard was found.
    var isAvailable: Bool { get }
    /// Current backlight level of the built-in keyboard (raw 0...1), or nil.
    func read() -> Float?
    /// Sets the built-in keyboard backlight; returns whether it took.
    func write(_ value: Float) -> Bool
}
