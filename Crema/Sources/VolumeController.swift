/// Actuator for volume adjustments (HUD slider, media keys).
/// `display == nil` targets the system output; a UUID targets that display's
/// own volume (external-display integration), so the contract already covers both.
protocol VolumeController: Sendable {
    /// Value normalized to 0...1.
    func setVolume(_ value: Double, on display: DisplayUUID?) async throws
    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws
}
