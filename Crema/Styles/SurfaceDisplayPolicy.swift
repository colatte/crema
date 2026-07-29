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
    /// Whether THIS display draws the current HUD. False on every panel but the
    /// one a display-scoped HUD names — a bar for another screen would be a
    /// control the user cannot aim (docs/DECISIONS.md: hud-belongs-to-its-display).
    var showsHUD = true
    /// Global "show playback controls": off is view-only (cover + text +
    /// scrubber, no transport buttons). Carried alongside showsNowPlaying since
    /// both are render context the panel updates on each frame pass.
    var showsControls = true
    /// The HUD level-indicator appearance (Card only). Render context like the
    /// flags above; the panel updates it on each frame pass from Preferences.
    var hudIndicatorStyle: HUDIndicatorStyle = .slider
    /// This panel's raw pointer signal, set by its own SurfaceHoverMonitor
    /// dispatch: the capsule knob reads it, so hovering one display's surface
    /// reveals the knob only there. The Coordinator's `pointerInside` stays
    /// the global mirror the timers key on.
    var pointerInside = false
}
