import Observation

/// Per-display presentation policy the panel injects into its view — rendering
/// context, like the slit inset, not domain state. With the window fixed and
/// never ordered out, hiding can no longer happen at the window level: a
/// display whose "show now playing here" is off must suppress the now-playing
/// content while still rendering HUDs. A reference box because the panel builds
/// its root view once; the flag is updated on every frame pass.
@Observable
@MainActor
final class SurfaceDisplayPolicy {
    var showsNowPlaying = true
    /// Global "show playback controls": off is view-only (cover + text +
    /// scrubber, no transport buttons). Carried alongside showsNowPlaying since
    /// both are render context the panel updates on each frame pass.
    var showsControls = true
}
