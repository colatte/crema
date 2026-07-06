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
enum PositionReconciliation {
    /// Above player rounding (≤ 1 s) plus tick granularity, below any
    /// deliberate seek.
    static let seekTolerance: Double = 2

    static func position(for update: NowPlaying, replacing previous: NowPlaying?) -> Double {
        guard let previous,
              previous.title == update.title,
              previous.artist == update.artist else {
            return update.position
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
