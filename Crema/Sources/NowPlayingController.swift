/// Actuator for media commands reported by the views (play/pause button,
/// scrubbing). Throws only on one-shot command failure — never for state.
protocol NowPlayingController: Sendable {
    func togglePlayPause() async throws
    /// Seeks to an absolute playback position in seconds.
    func seek(to seconds: Double) async throws
    func nextTrack() async throws
    func previousTrack() async throws
}
