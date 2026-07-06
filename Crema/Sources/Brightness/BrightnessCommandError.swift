/// Errors from the brightness actuators. `throws` is for one-shot command
/// failures — availability is state, reported separately.
enum BrightnessCommandError: Error {
    /// The private backend is unavailable (symbol/class missing or degraded).
    case unavailable
    /// The write reached the backend but the system rejected it.
    case writeFailed
    /// External-display brightness is the optional integration's job,
    /// never DDC here — the signature is preserved but non-nil is rejected.
    case externalDisplayUnsupported
}
