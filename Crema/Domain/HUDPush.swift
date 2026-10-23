/// A step key pressed against the end of the scale it points to: volume-up at
/// full, brightness-down at zero. The level cannot follow, so the bar answers
/// the press by pulling past that end until the key lets go
/// (docs/DECISIONS.md: the-bar-answers-the-press).
struct HUDPush: Equatable, Sendable {
    /// The two ends of a bar, named by the level they hold rather than by a side
    /// of the screen: which side holds which turns with the axis and the
    /// language, and the bar resolves that where it draws.
    enum End: Equatable, Sendable {
        /// Where the level is zero.
        case start
        /// Where the level is full.
        case end
    }

    var kind: SystemHUD.Kind
    var end: End

    /// Nil for mute, which is a toggle and points at no end.
    init?(key: MediaKey) {
        switch key {
        case .volumeUp: self.init(kind: .volume, end: .end)
        case .volumeDown: self.init(kind: .volume, end: .start)
        case .screenBrightnessUp: self.init(kind: .screenBrightness, end: .end)
        case .screenBrightnessDown: self.init(kind: .screenBrightness, end: .start)
        case .keyboardBrightnessUp: self.init(kind: .keyboardBrightness, end: .end)
        case .keyboardBrightnessDown: self.init(kind: .keyboardBrightness, end: .start)
        case .mute: return nil
        }
    }

    init(kind: SystemHUD.Kind, end: End) {
        self.kind = kind
        self.end = end
    }

    /// The end this press pulls on a bar showing `kind`; nil on a bar of another
    /// kind, which the press is not about.
    func end(for kind: SystemHUD.Kind) -> End? {
        self.kind == kind ? end : nil
    }
}
