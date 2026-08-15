/// Pure step arithmetic for native-OSD suppression: once the tap consumes a
/// key, the system no longer applies the change — the app becomes the only
/// applier and owes the user the native feel. Native scale: 16 steps across
/// the 0...1 range; holding Option+Shift switches to quarter-steps (64).
enum MediaKeyStepper {
    private static let coarseStep: Double = 1.0 / 16.0
    /// Internal (not private like its coarse sibling): OSDApplyVerification
    /// reads it to size the verify tolerance under a fine step.
    static let fineStep: Double = 1.0 / 64.0

    /// The next value for a step key from the current normalized value,
    /// clamped to 0...1. Nil for keys that are not steps (mute is a toggle,
    /// not arithmetic).
    static func next(from current: Double, key: MediaKey, fine: Bool) -> Double? {
        guard let delta = delta(for: key, fine: fine) else { return nil }
        return min(1, max(0, current + delta))
    }

    private static func delta(for key: MediaKey, fine: Bool) -> Double? {
        let step = fine ? fineStep : coarseStep
        switch key {
        case .volumeUp, .screenBrightnessUp, .keyboardBrightnessUp:
            return step
        case .volumeDown, .screenBrightnessDown, .keyboardBrightnessDown:
            return -step
        case .mute:
            return nil
        }
    }
}
