/// Decides whether a forwarded now-playing snapshot is a quiet boundary at
/// which the chain may cut a lower-priority source over to a recovered
/// higher-priority one without a visible mid-track flicker (audit A4).
///
/// Quiet boundaries: the track is paused/stopped (a), or its identity changed
/// from the previous snapshot (b). A still-playing continuation of the same
/// track is not a boundary — a promotion armed while it plays waits. The
/// "source emitted nothing since selection" boundary (c) is handled at the
/// chain (a silent source never reaches this predicate), not here.
enum PromotionBoundary {
    static func isQuiet(_ current: NowPlaying, previous: NowPlaying?) -> Bool {
        if !current.isPlaying { return true }
        // First playing emission (no prior identity) is mid-track, not a
        // boundary: cutting over on it would flicker the surface the user is
        // already watching.
        guard let previous else { return false }
        return current.title != previous.title || current.artist != previous.artist
    }
}
