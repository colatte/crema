/// Border seam for the internal display's brightness. The real implementation
/// (DisplayServicesBridge) resolves private symbols; a fake drives tests. This
/// is what makes "symbol present → available / absent → degrade" unit-testable
/// without touching the real private API.
protocol ScreenBrightnessBackend: Sendable {
    /// True only when the private symbols resolved.
    var isAvailable: Bool { get }
    /// Current internal-display brightness (raw 0...1), or nil if unreadable.
    func read() -> Float?
    /// Sets the internal-display brightness; returns whether it took.
    func write(_ value: Float) -> Bool
}
