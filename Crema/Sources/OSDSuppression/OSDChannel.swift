/// The suppressor's view of one adjustable quantity: read the current
/// normalized value (0…1) and apply a new one. With the native key consumed,
/// read → step → apply → read-back is the user's control path — real
/// implementations wrap the actuators plus the matching border reads;
/// mocks drive the apply-verify tests.
protocol OSDChannel: Sendable {
    /// Whether the quantity exists on the current hardware/route at all —
    /// false for HDMI/USB outputs without a volume control, Macs without a
    /// keyboard backlight. The native handler no-ops there (the "prohibited"
    /// HUD); the suppressor mirrors that instead of treating an absent
    /// capability as a broken write path.
    func isAvailable() -> Bool
    func read() -> Double?
    func apply(_ value: Double) async throws
}

/// Volume adds the mute plane (a toggle, not a step) — with its own
/// availability: plenty of output devices expose volume but no mute.
protocol OSDVolumeChannel: OSDChannel {
    func supportsMute() -> Bool
    func readMuted() -> Bool?
    func setMuted(_ muted: Bool) async throws
}
