/// Sends media commands through one active now-playing backend (adapter or
/// JXA). A throw means the command was not dispatched — on macOS 26.x the write
/// path (MediaRemote send) may be blocked even when reads work, and the adapter
/// reports that via a non-zero exit; JXA reports it when Automation is denied.
/// The Coordinator turns a throw into the "commands unavailable" degraded state.
protocol NowPlayingCommandChannel: Sendable {
    func togglePlayPause() async throws
    /// Seeks to an absolute position in seconds.
    func seek(to seconds: Double) async throws
    func nextTrack() async throws
    func previousTrack() async throws
}

enum NowPlayingCommandError: Error {
    /// No source is currently active, so there is nothing to command.
    case noActiveSource
    /// The backend dispatched but failed — most often a platform block.
    case commandFailed
}
