/// Sends media commands through one active now-playing backend (adapter or
/// JXA). A throw means the command did not land, and the Coordinator turns it
/// into the "commands unavailable" degraded state until the next surfacing event
/// re-earns it.
///
/// It does NOT mean the platform blocks writes. That claim used to be here and it
/// is false: measured on macOS 26.5.2, the adapter's `send` exits 0 and moves the
/// player, and both `MRMediaRemoteSendCommand` and
/// `MRMediaRemoteGetNowPlayingInfo` still resolve through dlopen — whatever the
/// platform restricted, it was never symbol availability, and the write is not
/// what broke. Reasons a throw is real: the adapter exiting non-zero, our own
/// 5 s timeout on a send whose XPC never returns, JXA with Automation denied, or
/// no active source at all. Attributing it to a platform block sends the next
/// reader looking for a wall that is not there.
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
    /// The backend was reached and the command did not land: a non-zero adapter
    /// exit, a send that outlived its timeout, or JXA refused.
    case commandFailed
}
