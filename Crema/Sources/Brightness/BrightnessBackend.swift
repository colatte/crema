/// Border seam for a brightness channel — one shape for both the internal
/// display and the built-in keyboard backlight. The real implementations
/// resolve private API (DisplayServicesBridge: dlopen/dlsym symbols;
/// CoreBrightnessKeyboardBridge: the private ObjC class plus the enumerated
/// built-in keyboard ID); a fake drives tests. This is what makes
/// "resolved → available / missing → degrade" unit-testable without touching
/// the real private API.
protocol BrightnessBackend: Sendable {
    /// Which screen this channel's readings speak for. A constant of the
    /// technology, never a lookup: the screen border governs the built-in panel
    /// and no other, and a keyboard backlight belongs to no screen at all. It
    /// lives here so the shared source can stamp it without asking the system
    /// anything on the emit path AND without a `kind` branch — one source type
    /// serves both channels over one emit line, so a target decided there rather
    /// than by the backend would scope the keyboard bar too
    /// (docs/DECISIONS.md: hud-target-is-a-role).
    var target: SystemHUD.Target { get }
    /// True only when the private API resolved (symbols for the screen; class
    /// and built-in keyboard ID for the backlight).
    var isAvailable: Bool { get }
    /// Current raw level (0...1), or nil if unreadable.
    func read() -> Float?
    /// Sets the level; returns whether it took.
    func write(_ value: Float) -> Bool
}
