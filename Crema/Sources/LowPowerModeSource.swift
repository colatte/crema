/// Capability: whether the machine is running in Low Power Mode right now.
///
/// The app's only consumer is presentation — the waveform's endless pulse stops
/// under it, exactly as it stops under Reduce Motion — so this is a system
/// reading that travels down to the views as rendering context, never domain
/// state. Polarity is the system's own: `true` = Low Power Mode is on = stop
/// spending on motion.
@MainActor
protocol LowPowerModeSource: AnyObject {
    /// The authoritative current state, readable synchronously so the first
    /// rendering is already correct: a Mac launched ALREADY in Low Power Mode
    /// posts no notification, and a consumer that only followed `updates` would
    /// animate until the user toggled the system setting off and on again.
    var isLowPower: Bool { get }

    /// Stream of readings. Each value is what an authoritative re-read returned,
    /// NOT a transition: the system's power-state edge fires for every power-source
    /// change (the charger going in or out) and not only when the Low Power switch
    /// moves, so an edge is a trigger and never a value. Repeats are therefore
    /// ordinary and are absorbed by the consumer's guarded write rather than
    /// filtered here — deduplicating at the source would make the meaning of an
    /// emission depend on what was emitted before it.
    var updates: AsyncStream<Bool> { get }
}
