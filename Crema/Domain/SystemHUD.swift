/// One system HUD event: what changed, to which level, and on which display.
struct SystemHUD: Equatable, Sendable {
    enum Kind: Equatable, Sendable, CaseIterable {
        case volume
        case screenBrightness
        case keyboardBrightness
    }

    var kind: Kind
    /// Normalized to 0...1; sources convert whatever scale the system uses.
    var value: Double
    var isMuted: Bool = false
    /// Originating display; nil means the internal display (the default).
    /// External-display sources populate it, keyed by display UUID.
    var display: DisplayUUID? = nil
}
