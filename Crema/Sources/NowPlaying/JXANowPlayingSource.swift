import Foundation

/// Fallback NowPlaying source via JavaScript for Automation (osascript) — the
/// plan B for when the adapter breaks. It queries the scriptable players
/// (Spotify, Music) directly, with no embedded binary.
///
/// Accepted limitations (documented on purpose): only covers scriptable apps
/// (a browser playing in a tab is invisible here — that is the adapter's job),
/// no artwork, and updates are polled on an interval so position moves in
/// steps, not smoothly. Each poll spawns a short osascript off the main thread.
final class JXANowPlayingSource: NowPlayingSource, StoppableSource, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let query: @Sendable () async -> String?
    private let clock: any SleepClock
    private let pollInterval: Double
    private let lock = NSLock()
    private var last: NowPlaying?
    private var pollTask: Task<Void, Never>?

    init(
        query: @escaping @Sendable () async -> String? = JXANowPlayingSource.runProbeScript,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2
    ) {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation = $0 }
        self.continuation = continuation
        self.query = query
        self.clock = clock
        self.pollInterval = pollInterval

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                do { try await clock.sleep(for: pollInterval) } catch { return }
            }
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
    }

    deinit { stop() }

    /// Available only when a scriptable player (Spotify/Music) actually has a
    /// track — not merely because osascript runs. Otherwise the chain could
    /// never reach the "off" state (browser-only playback is invisible to JXA),
    /// and the menu's degraded signal would never show.
    func isAvailable() async -> Bool {
        await query().flatMap(JXANowPlayingTranslation.nowPlaying(fromJSON:)) != nil
    }

    /// Probe availability without creating a polling source (runs the script
    /// once) — for the chain's candidate check.
    static func probeAvailability() async -> Bool {
        await runProbeScript().flatMap(JXANowPlayingTranslation.nowPlaying(fromJSON:)) != nil
    }

    func stop() {
        pollTask?.cancel()
        continuation.finish()
    }

    private func poll() async {
        let nowPlaying = await query().flatMap(JXANowPlayingTranslation.nowPlaying(fromJSON:))
        guard let nowPlaying else {
            markNothingPlaying()
            return
        }
        let changed = lock.withLock {
            let didChange = nowPlaying != last
            last = nowPlaying
            return didChange
        }
        if changed { continuation.yield(nowPlaying) }
    }

    private func markNothingPlaying() {
        lock.lock()
        guard var nowPlaying = last, nowPlaying.isPlaying else { lock.unlock(); return }
        nowPlaying.isPlaying = false
        last = nowPlaying
        lock.unlock()
        continuation.yield(nowPlaying)
    }

    /// Real probe: reads the current track from the active player (the shared
    /// JXAPlayerScript preamble — the same selection the command side uses).
    /// Spotify reports duration in milliseconds, Music in seconds — normalized
    /// here via the preamble's isSpotify flag.
    private static let probeSource = """
    (function() {
    \(JXAPlayerScript.preamble)
      return JSON.stringify(withActivePlayer(function(app, state, isSpotify) {
        const t = app.currentTrack;
        const dur = t.duration();
        return {
          title: t.name(),
          artist: t.artist(),
          duration: isSpotify ? dur / 1000 : dur,
          position: app.playerPosition(),
          playing: state === 'playing'
        };
      }) || {});
    })();
    """

    @Sendable
    private static func runProbeScript() async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", probeSource]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        // The osascript reply is bounded by the AppleEvent timeout (~1-2 min),
        // but a probe holding the chain's selection that long is still a stall;
        // cap it so a stuck query can't wedge fallback. nil output reads as
        // "nothing playing" — the probe's honest degraded answer.
        return await runChildProcess(
            process,
            readingStdout: pipe,
            timeout: 10,
            clock: ContinuousSleepClock(),
            failureValue: nil
        ) { _, output in output }
    }
}
