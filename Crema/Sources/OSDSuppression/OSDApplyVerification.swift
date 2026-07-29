/// Pure verdict on an applied step: with the native key consumed, a write that
/// silently does nothing leaves the user without volume control, so the suppressor
/// reads the value back after every apply.
///
/// A false verdict SUSPENDS THAT ONE DOMAIN — it does not disengage. Disengaging
/// globally on the first failure is what this used to say, and what the code used
/// to do: one channel's failure killed suppression for all three and persisted the
/// preference off (docs/DECISIONS.md: J5-raio-global, per-domain-suspension).
enum OSDApplyVerification {
    /// Half a fine step of slack for float round-trips and hardware grids.
    /// Accepted blind spot: a dead write whose target lands within this band
    /// of the current value (a step clamped nearly at a boundary) passes —
    /// tightening it would false-alarm on quantized hardware (the keyboard
    /// backlight's coarse levels legitimately don't move for a fine step);
    /// the next full step falls outside the band and catches a truly dead
    /// path.
    static let tolerance = MediaKeyStepper.fineStep / 2

    static func verified(before: Double, target: Double, after: Double?) -> Bool {
        guard let after else { return false }
        // Pinned at a boundary: the step had nowhere to go (volume-up at 1),
        // exactly like the native handler's no-op at the ends of the scale.
        if target == before { return true }
        if abs(after - target) <= tolerance { return true }
        // Hardware may quantize writes to its own grid (keyboard backlight
        // has coarse levels); movement in the commanded direction still
        // proves the write path is alive.
        return (target - before) * (after - before) > 0
    }
}
