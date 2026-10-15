/// Reads the system output's level on demand, as the reading a volume change
/// would carry: a read, never a write. For a HUD the app puts up without a key
/// behind it (the Card placement preview), where the level shown has to be the
/// one the output is really at. Nil when there is nothing to read (no output
/// device, a failed read) — never a fabricated level.
protocol VolumeReading: Sendable {
    func currentVolume() async -> SystemHUD?
}
