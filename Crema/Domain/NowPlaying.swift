/// Snapshot of the media currently playing, in the app's own vocabulary.
/// Sources translate their wire formats (adapter output, JXA) into this type
/// at the border — nothing above the sources ever sees those formats.
struct NowPlaying: Equatable, Sendable {
    var title: String
    var artist: String? = nil
    /// Raw encoded image bytes (PNG/JPEG); decoded by the view layer.
    var artworkData: [UInt8]? = nil
    var isPlaying: Bool
    /// Playback position in seconds (drives scrubbing).
    var position: Double
    /// Track length in seconds; nil when the player reports none (e.g. live streams).
    var duration: Double? = nil
    /// Bundle ID of the app providing the media — the parent app when the
    /// system reports a helper process (browsers play through WebKit
    /// helpers). Nil when the source cannot tell (the JXA fallback). Drives
    /// the browser-media filter.
    var sourceBundleID: String? = nil
    /// Whether the media allows track skipping (radio/live content prohibits
    /// it). This metadata is the only honest gate: a skip command to
    /// prohibiting media is delivered successfully and silently ignored, so
    /// the failure-driven degradation never sees it. True when the source
    /// doesn't report it (the JXA fallback).
    var supportsSkip: Bool = true
}
