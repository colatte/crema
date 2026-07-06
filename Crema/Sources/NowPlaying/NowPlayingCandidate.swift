/// One rung of the now-playing fallback chain: how to check whether this source
/// can work right now, how to make a fresh instance of it (a factory, not a
/// stored source, so the chain can rebuild a dead source on re-selection), and
/// the command channel to use while this candidate is active (so commands go
/// through the same backend as the active source).
struct NowPlayingCandidate {
    let isAvailable: @Sendable () async -> Bool
    let makeSource: @Sendable () -> any NowPlayingSource
    let commandChannel: any NowPlayingCommandChannel
}
