/// Snapshot of the media currently playing, in the app's own vocabulary.
/// Sources translate their wire formats (adapter output, JXA) into this type
/// at the border — nothing above the sources ever sees those formats.
struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String?
    /// Raw encoded image bytes (PNG/JPEG); decoded by the view layer.
    var artworkData: [UInt8]?
    /// The album, when the source reports one. Unread by any view — the
    /// surfaces show title and artist, and a third line would crowd them — and
    /// kept as the seed of the cover upgrade, where album turns a fuzzy
    /// two-term search into an accurate three-term one (docs/DECISIONS.md:
    /// the-click-was-the-last-thing-holding-the-lookup-up).
    var album: String?
    var isPlaying: Bool
    /// Playback position in seconds (drives scrubbing).
    var position: Double
    /// Track length in seconds; nil when the player reports none (e.g. live streams).
    var duration: Double?
    /// Bundle ID of the app providing the media — the parent app when the
    /// system reports a helper process (browsers play through WebKit
    /// helpers). Nil when the source cannot tell (the JXA fallback). Drives
    /// the browser-media filter.
    var sourceBundleID: String?
    /// Whether the media allows track skipping (radio/live content prohibits
    /// it). This metadata is the only honest gate: a skip command to
    /// prohibiting media is delivered successfully and silently ignored, so
    /// the failure-driven degradation never sees it. True when the source
    /// doesn't report it (the JXA fallback).
    var supportsSkip: Bool = true
}

extension NowPlaying {
    /// The longest position the app represents: a day, the same bound the
    /// adapter's duration sanitizer keeps. Whoever publishes now-playing chooses
    /// this number (any app, and websites when browser media is on), and past
    /// Int64's seconds the time label's `Duration` traps (measured: 1e19 s
    /// aborts), so every border bounds a position before the domain carries it.
    static let maximumPosition: Double = 24 * 60 * 60

    /// A position in `0...(duration ?? maximumPosition)`; NaN reads as 0.
    static func bounded(position: Double, duration: Double?) -> Double {
        guard !position.isNaN else { return 0 }
        return min(max(position, 0), duration ?? maximumPosition)
    }
}
