/// The post-seek authority window over the shown position: from the
/// scrubber's release until the stream itself flows at ≈ the target (the
/// player's echo, the adapter's re-anchored ticker, or the first post-seek
/// poll), a stale stream position must not clobber what the user just set.
/// Reconciliation alone cannot tell the two apart: a deliberate sub-tolerance
/// seek reads exactly like the anchor jitter the same tolerance was written to
/// absorb — presumed parity between two paths that only look alike
/// (docs/DECISIONS.md: J4-paridade-presumida), and the scrubber's cousin of the
/// brightness drag. Pure decision + target storage; the Coordinator owns the
/// timeout timer that calls `end()` (the honest fallback — the override is
/// never stuck; docs/DECISIONS.md: scrub-grace).
struct ScrubGrace: Sendable {
    /// Sized to outlive the JXA poll (2 s) and the one-shot command
    /// latencies; on expiry the stream takes back over unconditionally. On
    /// the adapter path the window rarely runs its course — the re-anchored
    /// ticker confirms within a tick — so its real work is the JXA poll gap
    /// and any source with no local extrapolation.
    static let defaultWindow: Double = 5.0
    /// One home for "did the echo land near the target?" — the same judgment
    /// the source-side hint makes (PositionReconciliation.seekConfirmTolerance).
    static let defaultConfirmTolerance: Double = PositionReconciliation.seekConfirmTolerance

    private(set) var target: Double?
    private let confirmTolerance: Double

    init(confirmTolerance: Double = Self.defaultConfirmTolerance) {
        self.confirmTolerance = confirmTolerance
    }

    mutating func begin(target seconds: Double) {
        target = seconds
    }

    mutating func end() {
        target = nil
    }

    /// Weighs a stream update against the seek in flight. Returns the position
    /// to re-apply over the update (a stale echo), or nil when the stream
    /// rules — no grace active, the stream confirmed (≈ target), or the track
    /// identity changed (a new track owns its own position); the two latter
    /// end the grace here.
    mutating func heldPosition(update: NowPlaying, previous: NowPlaying?) -> Double? {
        guard let target else { return nil }
        let identityChanged = previous == nil
            || previous?.title != update.title
            || previous?.artist != update.artist
        if identityChanged || abs(update.position - target) <= confirmTolerance {
            end()
            return nil
        }
        return target
    }
}
