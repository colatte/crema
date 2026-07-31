/// Capability: reports whether the current moment is safe to suppress the
/// native OSD. "Safe" means the user is actually at the machine and can see the
/// app's own HUD — the console session is active (on-console) and the screen is
/// unlocked. Locked or fast-user-switched away is unsafe: third-party code
/// cannot draw over the lock shield (proven on hardware — see
/// docs/LOCKSCREEN-INVESTIGATION.md), so suppression must step aside
/// and let the native OSD — which does render on the lock screen — back through.
///
/// Polarity is fixed and semantic: `true` = safe to suppress (unlocked AND
/// on-console); `false` = suspend suppression (locked OR off-console). The read
/// side never touches the user preference — engagement policy lives above this
/// source, in the wiring.
@MainActor
protocol ScreenLockSource: AnyObject {
    /// The authoritative current state, readable synchronously so the first
    /// engagement is correct at launch (launched-while-locked must not engage).
    var isSuppressionSafe: Bool { get }

    /// Stream of state changes. Each value is the reconciled authoritative
    /// state (an edge notification only prompts a re-read; the poll is the sole
    /// input), deduplicated so only real transitions emit.
    var updates: AsyncStream<Bool> { get }
}
