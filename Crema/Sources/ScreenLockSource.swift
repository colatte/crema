/// Capability: reports whether the current moment is safe to suppress the
/// native OSD. "Safe" means the user is actually at the machine and can see the
/// app's own HUD — the console session is active (on-console) and the screen is
/// unlocked. Locked or fast-user-switched away is unsafe: this app draws no HUD
/// over the lock shield, so suppression must step aside and let the native OSD —
/// which does render on the lock screen — back through. Not a wall, a choice: no
/// window level reaches the shield (proven on hardware), but the shield is a
/// SPACE, and the private path over it not only exists — the app already takes
/// it, for the opt-in now-playing widget and for nothing else. Spending it on
/// the HUDs is a separate decision nobody has made (docs/DECISIONS.md:
/// the-lock-screen-is-a-space; docs/LOCKSCREEN-INVESTIGATION.md).
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
