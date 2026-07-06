/// NowPlayingController that routes each command to the currently active
/// backend's channel (adapter when the chain is on the adapter, JXA when it fell
/// back) — the same channel as the active source, never a parallel one. The
/// channel is resolved per command from the chain, so a mid-session fallback
/// switches the command path too. Throws when nothing is active.
struct RoutingNowPlayingController: NowPlayingController {
    let activeChannel: @Sendable () -> (any NowPlayingCommandChannel)?

    func togglePlayPause() async throws {
        guard let channel = activeChannel() else { throw NowPlayingCommandError.noActiveSource }
        try await channel.togglePlayPause()
    }

    func seek(to seconds: Double) async throws {
        guard let channel = activeChannel() else { throw NowPlayingCommandError.noActiveSource }
        try await channel.seek(to: seconds)
    }

    func nextTrack() async throws {
        guard let channel = activeChannel() else { throw NowPlayingCommandError.noActiveSource }
        try await channel.nextTrack()
    }

    func previousTrack() async throws {
        guard let channel = activeChannel() else { throw NowPlayingCommandError.noActiveSource }
        try await channel.previousTrack()
    }
}
