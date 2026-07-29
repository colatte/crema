/// Actuator for volume adjustments (HUD slider, media keys).
///
/// `display == nil` targets the system output. A UUID would target that display's
/// own volume, and NOTHING implements it — the only conformer throws
/// `externalDisplayUnsupported`, because external-display audio runs over DDC,
/// which Core Audio cannot see and this app will not drive itself. The parameter
/// is here so the day an integration can answer it, the shape does not change; it
/// is not a capability the protocol delivers today.
protocol VolumeController: Sendable {
    /// Value normalized to 0...1.
    func setVolume(_ value: Double, on display: DisplayUUID?) async throws
    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws
}
