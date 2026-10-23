/// A step key held down: volume-up, brightness-down and their kin. The bar answers
/// it the way UIKit's fluid slider answers the iPhone's volume buttons: it scales
/// while the key is down, and each press that finds the level already at the end
/// the key points to pushes it past that end
/// (docs/DECISIONS.md: the-bar-answers-the-press).
struct HUDPress: Equatable, Sendable {
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
    /// The end the key points to.
    var end: End
    /// Presses of this hold that found the level already at `end`.
    var stepsPastEnd = 0

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

    init(kind: SystemHUD.Kind, end: End, stepsPastEnd: Int = 0) {
        self.kind = kind
        self.end = end
        self.stepsPastEnd = stepsPastEnd
    }

    /// Whether `key` is the key this press is of.
    func isOf(_ key: MediaKey) -> Bool {
        guard let other = Self(key: key) else { return false }
        return other.kind == kind && other.end == end
    }

    /// This press as a bar showing `kind` answers it; nil on a bar of another
    /// kind, which the press is not about.
    func `for`(_ kind: SystemHUD.Kind) -> Self? {
        self.kind == kind ? self : nil
    }
}
