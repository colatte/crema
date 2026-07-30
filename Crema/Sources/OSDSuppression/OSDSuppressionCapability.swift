/// The four independent controls the suppressor writes through — a FINER grain
/// than `OSDSuppressionDomain`, and deliberately so. Mute is a control of its own
/// even though it shares the volume domain's recovery: `supportsVolume` and
/// `supportsMute` are two separate Core Audio properties on the same device, and
/// plenty of outputs answer yes to one and no to the other. Marking the DOMAIN
/// when only the mute plane is missing would hand the volume keys back on hardware
/// whose volume works perfectly — losing the app's own bar for the domain that is
/// the core of the feature.
///
/// An absent capability is not a failure. There is nothing malfunctioning, nothing
/// for a recovery probe to fix and nothing to warn about, so it never suspends a
/// domain, never counts toward escalation and never reaches the menu. What it does
/// is hand that key back, because a consumed key always owes feedback and this app
/// has none to give for a control that does not exist — the system does, and draws
/// it (docs/DECISIONS.md: absent-capability-hands-the-key-back).
enum OSDSuppressionCapability: Sendable {
    case volumeLevel
    case mute
    case screenBrightness
    case keyboardBrightness

    /// Which capability a key needs before this app can take it — the GATE
    /// direction, and 1:1. The reverse is not: a volume-up press consults both the
    /// volume level and, for its unmute-first step, the mute plane. So what gets
    /// LEARNED is named by the guard that answered, never derived from the key that
    /// ran it; deriving it would mark the level absent on a device whose level is
    /// fine and whose mute plane simply does not exist.
    init(_ key: MediaKey) {
        switch key {
        case .volumeUp, .volumeDown: self = .volumeLevel
        case .mute: self = .mute
        case .screenBrightnessUp, .screenBrightnessDown: self = .screenBrightness
        case .keyboardBrightnessUp, .keyboardBrightnessDown: self = .keyboardBrightness
        }
    }
}
