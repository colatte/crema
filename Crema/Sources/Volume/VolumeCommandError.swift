/// Errors from the volume actuator. Named for the capability (not the
/// technology) so any VolumeController implementation can throw it — the
/// BrightnessCommandError mold. `throws` is for one-shot command failures —
/// availability is state, reported separately.
enum VolumeCommandError: Error {
    /// External-display volume is the optional integration's job, never
    /// handled here — the signature is preserved but non-nil is rejected.
    case externalDisplayUnsupported
    /// No default output device existed at the instant of the write (the
    /// AirPods/headphones disconnect window).
    case noOutputDevice
}
