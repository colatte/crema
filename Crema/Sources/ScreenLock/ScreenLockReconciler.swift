/// Pure reconciliation for the screen-lock source, kept above the system border
/// so every decision is unit-tested without touching CoreGraphics.
///
/// The design the investigation calls "camadas": the fast edges
/// (`com.apple.screenIsLocked/Unlocked`, session activate/resign) carry
/// latency, but an edge never directly flips the state — it only prompts a
/// re-read of the authoritative poll (`CGSSessionScreenIsLocked` +
/// `kCGSSessionOnConsoleKey`). The reconciled authoritative reading is the sole
/// input to what we emit; the edge is just the trigger. Transitions are
/// deduplicated so a redundant edge (or a poll that confirms no change) is
/// silent.
struct ScreenLockReconciler {
    private(set) var lastSafe: Bool

    init(locked: Bool, onConsole: Bool) {
        lastSafe = Self.isSuppressionSafe(locked: locked, onConsole: onConsole)
    }

    /// Suppression is safe only when the user is present at an active session:
    /// unlocked and on-console. Fast-user-switch (off-console) counts as away.
    static func isSuppressionSafe(locked: Bool, onConsole: Bool) -> Bool {
        !locked && onConsole
    }

    /// Feed a fresh authoritative reading (taken after an edge, or an initial
    /// poll). Returns the new state to emit, or nil when it matches the last —
    /// so an edge that confirms the current truth produces no spurious flip.
    mutating func reconcile(locked: Bool, onConsole: Bool) -> Bool? {
        let safe = Self.isSuppressionSafe(locked: locked, onConsole: onConsole)
        guard safe != lastSafe else { return nil }
        lastSafe = safe
        return safe
    }
}
