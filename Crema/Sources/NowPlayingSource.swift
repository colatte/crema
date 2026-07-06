/// Event source for the currently playing media.
protocol NowPlayingSource: Sendable {
    /// Single-consumer stream of domain updates. A finished stream means the
    /// source became unavailable — availability is state, not a fatal error;
    /// the consumer re-evaluates the fallback chain.
    var updates: AsyncStream<NowPlaying> { get }
    func isAvailable() async -> Bool
}
