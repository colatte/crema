/// Event source for the currently playing media.
protocol NowPlayingSource: Sendable {
    /// Single-consumer stream of domain updates. A finished stream means the
    /// source became unavailable — availability is state, not a fatal error;
    /// the consumer re-evaluates the fallback chain.
    var updates: AsyncStream<NowPlaying> { get }
    func isAvailable() async -> Bool
    /// The user deliberately sought to this position (the scrubber's release).
    /// The seek COMMAND travels a separate one-shot channel with no path back
    /// to the source, so a source that extrapolates position locally (the
    /// adapter's 1 Hz ticker) would keep counting from the pre-seek anchor and
    /// rewind the shown position until the player's own echo lands — this hint
    /// is how it re-anchors instead. Sources with no local extrapolation
    /// (JXA's raw poll) take the no-op default.
    func noteSeek(to seconds: Double)
    /// The seek command failed or never reached a player: the optimistic
    /// re-anchor was a lie — the source restores its pre-seek line so the
    /// ticker stops counting from a position the player never reached.
    func noteSeekFailed()
}

extension NowPlayingSource {
    func noteSeek(to seconds: Double) {}
    func noteSeekFailed() {}
}
