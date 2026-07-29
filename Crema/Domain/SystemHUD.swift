/// One system HUD event: what changed, to which level, and on which display.
struct SystemHUD: Equatable, Sendable {
    enum Kind: Equatable, Sendable, CaseIterable {
        case volume
        case screenBrightness
        case keyboardBrightness
    }

    /// Who produced this reading, and therefore who a drag on it must be sent
    /// back to. The two do not measure the same thing: an app that blends
    /// hardware brightness with software dimming reports its blended level, while
    /// the system's own reading is the hardware one — so a bar drawn from one and
    /// dragged into the other writes a level the user did not aim at
    /// (docs/DECISIONS.md: betterdisplay-osd-source).
    enum Authority: Equatable, Sendable {
        case system
        case betterDisplay
    }

    var kind: Kind
    /// Normalized to 0...1; sources convert whatever scale the system uses.
    var value: Double
    var isMuted: Bool = false
    /// Originating display; nil means the internal display (the default).
    /// External-display sources populate it, keyed by display UUID.
    var display: DisplayUUID?
    var authority: Authority = .system

    /// The same reading at a new level — what a drag on this HUD produced, kept
    /// on its own scale, display and authority so the echo lands where the bar is.
    func at(_ value: Double) -> Self {
        var copy = self
        copy.value = value
        return copy
    }

    /// The same reading credited to another authority — what a write that had to
    /// fall back reports, so the next drag goes where this one actually landed.
    func by(_ authority: Authority) -> Self {
        var copy = self
        copy.authority = authority
        return copy
    }
}
