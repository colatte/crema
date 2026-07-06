/// Pure conversions between the system's raw volume values and the domain's
/// normalized 0...1. No Core Audio here — this is the testable part above the
/// border, and the defensive clamp that guarantees the domain never receives
/// a value outside 0...1.
enum VolumeConversion {
    /// Raw system value → domain value. Non-finite input degrades to 0.
    static func normalize(_ raw: Float) -> Double {
        guard !raw.isNaN else { return 0 }
        return Double(min(max(raw, 0), 1))
    }

    /// Domain/slider value → value for the system, same defensive clamp.
    static func denormalize(_ value: Double) -> Float {
        guard !value.isNaN else { return 0 }
        return Float(min(max(value, 0), 1))
    }

    /// Builds the domain event from raw readings. Mute is a passthrough; the
    /// mapping lives here so the whole raw→domain step is testable in one place.
    static func hud(rawVolume: Float, isMuted: Bool) -> SystemHUD {
        SystemHUD(kind: .volume, value: normalize(rawVolume), isMuted: isMuted)
    }
}
