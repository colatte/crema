/// Decides the shown position when a fresh (already time-compensated) anchor
/// replaces the last shown snapshot. The compensation makes the anchor
/// accurate; this keeps it monotonic and correct across the play-state
/// transitions, where the anchors are least trustworthy. It is a pure function
/// of the two snapshots — the whole state machine is unit-tested.
///
/// The transitions, each a distinct rule:
/// - resume (paused → playing): resync to the anchor immediately, so playback
///   flows from the player's true position with no dwell. A backward seek made
///   while paused surfaces here and is honored.
/// - pause / still paused (→ paused): freeze at the last shown position. Pause
///   payloads routinely report 0 or drop the elapsed key, which must never
///   collapse the scrubber to the start; only a forward anchor moves it. The
///   cost, accepted: a real backward seek made while paused is
///   indistinguishable from that dropped 0, so it holds the old value for the
///   rest of the pause and the resume resync is what lands the seeked point.
/// - playing (playing → playing): a small backward step is anchor jitter
///   (sub-second rounding vs. whole-second ticks) and holds; a larger one is a
///   real backward seek and is obeyed.
/// - Fresh start / track change (no previous, or a different identity): take
///   the anchor, including repeat-one restarting the same title at 0.
/// - Deliberate seek in flight (`pendingSeek`, the scrubber's release): an
///   anchor near the target is the player echoing that seek and is obeyed
///   even where the rules above would hold it — the sub-tolerance backward
///   step of a precision micro-scrub, and the paused freeze (whose "dropped
///   0" heuristic still wins when the echo IS a paused 0 and the target is
///   not the start — that 0 is the known lie, not a confirmation). Any OTHER
///   anchor while the seek flies is the pre-seek line still echoing and is
///   HELD — in either direction, since a stale anchor sits before a forward
///   seek's target and after a backward one's. The hold is bounded by the
///   caller: the hint dies on confirmation, track change, an exhausted
///   anchor budget, or a failed command — never held forever.
enum PositionReconciliation {
    /// Above player rounding (≤ 1 s) plus tick granularity, below any
    /// deliberate seek.
    static let seekTolerance: Double = 2
    /// How close an anchor must land to a pending seek target to read as the
    /// player confirming it — playback advances while the command flies, so
    /// exact equality never happens. Shared with the source's hint lifecycle.
    static let seekConfirmTolerance: Double = 3

    static func position(
        for update: NowPlaying,
        replacing previous: NowPlaying?,
        pendingSeek: Double? = nil
    ) -> Double {
        guard let previous,
              previous.title == update.title,
              previous.artist == update.artist else {
            return update.position
        }

        if let pendingSeek {
            let nearTarget = abs(update.position - pendingSeek) <= seekConfirmTolerance
            let pausedZeroLie = !update.isPlaying && update.position == 0 && pendingSeek > 0
            if nearTarget, !pausedZeroLie {
                return update.position
            }
            return previous.position
        }

        switch (previous.isPlaying, update.isPlaying) {
        case (false, true):
            return update.position
        case (_, false):
            return max(previous.position, update.position)
        case (true, true):
            let regressed = previous.position - update.position
            return (regressed > 0 && regressed < seekTolerance) ? previous.position : update.position
        }
    }
}
