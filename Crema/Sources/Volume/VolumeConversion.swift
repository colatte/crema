/// Pure conversions between the system's raw volume values and the domain's
/// normalized 0...1. No Core Audio here — this is the testable part above the
/// border, and the defensive clamp that guarantees the domain never receives
/// a value outside 0...1.
enum VolumeConversion {
    /// The normalized scale ends, shared with the boundary-refresh rule below.
    private static let minValue: Double = 0
    private static let maxValue: Double = 1

    /// Raw system value → domain value. NaN needs the explicit guard because it
    /// compares false against everything and would pass through the clamp intact;
    /// the infinities do not — they saturate to the near end like any
    /// out-of-range reading, so +∞ lands on 1 and -∞ on 0.
    static func normalize(_ raw: Float) -> Double {
        guard !raw.isNaN else { return 0 }
        return Double(min(max(raw, 0), 1))
    }

    /// Domain/slider value → value for the system, same defensive clamp and the
    /// same non-finite handling (NaN to 0, the infinities to the near end).
    static func denormalize(_ value: Double) -> Float {
        guard !value.isNaN else { return 0 }
        return Float(min(max(value, 0), 1))
    }

    /// Builds the domain event from raw readings. Mute is a passthrough; the
    /// mapping lives here so the whole raw→domain step is testable in one place.
    /// No display target, here and in the boundary refresh below: volume is the
    /// default output device's, so no screen owns it and its bar belongs on every
    /// panel — and the actuator refuses a named display outright, which makes this
    /// a contract of actuation and not only of presentation
    /// (docs/DECISIONS.md: hud-target-is-a-role).
    static func hud(rawVolume: Float, isMuted: Bool) -> SystemHUD {
        SystemHUD(kind: .volume, value: normalize(rawVolume), isMuted: isMuted)
    }

    /// The HUD a consumed volume key owes at a scale boundary. Contract: a
    /// consumed media key always produces feedback; at the boundary the write
    /// is a clamped no-op that fires no Core Audio property-change echo, so the
    /// source re-reads and emits here to reproduce native's full/empty-bar
    /// flash. Nil off the boundary — mid-scale the write moves the value and the
    /// echo already covers it, so emitting would double-fire.
    static func boundaryRefreshHUD(rawVolume: Float, isMuted: Bool) -> SystemHUD? {
        let value = normalize(rawVolume)
        guard value == minValue || value == maxValue else { return nil }
        return SystemHUD(kind: .volume, value: value, isMuted: isMuted)
    }
}
