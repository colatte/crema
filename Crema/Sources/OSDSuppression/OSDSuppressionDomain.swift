/// The three independent channels the native-OSD suppressor consumes. Each
/// recovers on its own: a failed volume apply must not strand brightness
/// suppression, and a dead keyboard-backlight write must not kill volume
/// suppression (the old behavior this replaced — one failure disengaged all
/// three and persisted the opt-in off; docs/DECISIONS.md: per-domain-suspension).
///
/// This is the fine-grained, per-domain health axis that lives *inside* one
/// engagement. It is orthogonal to — and coarser than — the lock-aware
/// suspension of the whole engagement (SuppressionLockController): locking
/// suspends the entire engagement (consumer nil); a failed apply suspends a
/// single domain within a still-active engagement. The two never coexist —
/// `setEngaged(false)` clears the per-domain state.
enum OSDSuppressionDomain: CaseIterable, Sendable {
    case volume
    case screenBrightness
    case keyboardBrightness

    /// Which domain a consumed key belongs to. Mute rides with volume — its
    /// unmute plane is part of the volume channel, so a mute failure and a
    /// volume failure share one recovery.
    init(_ key: MediaKey) {
        switch key {
        case .mute, .volumeUp, .volumeDown: self = .volume
        case .screenBrightnessUp, .screenBrightnessDown: self = .screenBrightness
        case .keyboardBrightnessUp, .keyboardBrightnessDown: self = .keyboardBrightness
        }
    }
}
