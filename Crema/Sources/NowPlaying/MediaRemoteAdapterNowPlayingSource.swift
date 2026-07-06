import Foundation

/// NowPlaying source backed by the mediaremote-adapter stream. Consumes the
/// adapter's raw lines, translates each into a
/// NowPlaying at the border (no JSON escapes), and emits.
///
/// The adapter only emits on MediaRemote changes, so a 1 Hz ticker advances the
/// position locally while playing and resyncs on every adapter update — this is
/// what keeps the scrubber moving between updates. Each resync goes through
/// PositionReconciliation so anchor jitter never rewinds the shown position
/// (the translation already ages the anchor to delivery time). When the line
/// stream ends (process died / EOF) the updates stream finishes, which is the
/// signal the chain uses to re-evaluate availability.
final class MediaRemoteAdapterNowPlayingSource: NowPlayingSource, StoppableSource, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let availability: @Sendable () async -> Bool
    private let clock: any SleepClock
    private let tickInterval: Double
    /// Injected so the anchor-aging math in the translation stays testable
    /// with fixed instants.
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var latest: NowPlaying?
    private var tickerGeneration = 0
    private var tickerTask: Task<Void, Never>?
    private var consumerTask: Task<Void, Never>?
    private var process: MediaRemoteAdapterProcess?

    init(
        lines: AsyncStream<String>,
        availability: @escaping @Sendable () async -> Bool,
        clock: any SleepClock = ContinuousSleepClock(),
        tickInterval: Double = 1,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation = $0 }
        self.continuation = continuation
        self.availability = availability
        self.clock = clock
        self.tickInterval = tickInterval
        self.now = now

        consumerTask = Task { [weak self] in
            for await line in lines {
                self?.consume(line)
            }
            self?.finishFromEOF()
        }
        continuation.onTermination = { [weak self] _ in self?.stop() }
    }

    /// Real wiring: runs the adapter with --no-diff (every line a full snapshot,
    /// so translation stays stateless). Artwork flows since the visual-richness
    /// round: the base64 fattens each line (~100–500 KB), which the line
    /// buffer takes in stride, and the views decode once per cover
    /// (ArtworkView/ArtworkAccent key their work on the bytes) — the original
    /// reasons for --no-artwork are both retired. The debug observer keeps the
    /// flag so raw-line logging stays readable. Probes availability via the
    /// `test` command.
    convenience init(paths: MediaRemoteAdapterPaths, clock: any SleepClock = ContinuousSleepClock()) {
        // --micros: whole-second ISO timestamps would defeat the anchor
        // aging — see the AdapterPayloadTranslation header.
        let process = MediaRemoteAdapterProcess(paths: paths, streamArguments: ["stream", "--no-diff", "--micros"])
        let probe = MediaRemoteAdapterProbe(paths: paths)
        self.init(lines: process.rawLines, availability: { await probe.isAvailable() }, clock: clock)
        lock.lock(); self.process = process; lock.unlock()
        process.start()
    }

    deinit { stop() }

    func isAvailable() async -> Bool { await availability() }

    func stop() {
        // Capture the handles under the lock, then act outside it — these
        // refs are reassigned by the consumer task while stop() may run from
        // onTermination / deinit / the chain on another thread.
        lock.lock()
        let consumer = consumerTask; let ticker = tickerTask; let runningProcess = process
        consumerTask = nil; tickerTask = nil
        lock.unlock()
        consumer?.cancel()
        ticker?.cancel()
        runningProcess?.stop()
        continuation.finish()
    }

    // Yields happen under the lock throughout: emission order must match the
    // order of `latest` writes, or a racing tick's yield lands after a fresh
    // anchor's with an older position — a one-tick backward blip downstream.
    // Safe: yield never blocks with .bufferingNewest, and yield never invokes
    // onTermination (only finish/cancel do, and those run outside the lock).

    private func consume(_ line: String) {
        guard var nowPlaying = AdapterPayloadTranslation.nowPlaying(fromLine: line, at: now()) else {
            markNothingPlaying()
            return
        }
        lock.lock()
        nowPlaying.position = PositionReconciliation.position(for: nowPlaying, replacing: latest)
        latest = nowPlaying
        tickerGeneration += 1
        let generation = tickerGeneration
        continuation.yield(nowPlaying)
        lock.unlock()
        restartTicker(playing: nowPlaying.isPlaying, generation: generation)
    }

    /// Empty payload = playback stopped. Re-emit the last track as not playing
    /// so the Coordinator hides it, and stop advancing.
    private func markNothingPlaying() {
        lock.lock()
        guard var nowPlaying = latest, nowPlaying.isPlaying else { lock.unlock(); return }
        nowPlaying.isPlaying = false
        latest = nowPlaying
        tickerGeneration += 1
        let ticker = tickerTask
        tickerTask = nil
        continuation.yield(nowPlaying)
        lock.unlock()
        ticker?.cancel()
    }

    /// stop() racing a mid-flight consume can see this install a ticker after
    /// stop already cancelled everything. That orphan is reaped by
    /// finishFromEOF (stop cancelled the consumer, so its loop exits there) —
    /// its ticker-cancel is not redundant with stop()'s; removing it would
    /// leak a self-retaining ticker.
    private func restartTicker(playing: Bool, generation: Int) {
        let newTicker = playing ? Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.clock.sleep(for: self.tickInterval) } catch { return }
                self.tick(ifCurrent: generation)
            }
        } : nil
        lock.lock()
        let oldTicker = tickerTask
        tickerTask = newTicker
        lock.unlock()
        oldTicker?.cancel()
    }

    /// A tick raced by a fresh anchor must not land: cancellation only covers
    /// the sleep, so a tick whose sleep already returned would add a full
    /// interval on top of an anchor just aged to delivery time — an overshoot
    /// the reconciliation would then hold for the rest of the track. The
    /// generation, bumped with every anchor-driven `latest` rewrite, is what
    /// invalidates those in-flight ticks. Internal (not private) so the race
    /// has a deterministic regression test — the timing can't be forced
    /// through the public stream.
    func tick(ifCurrent generation: Int) {
        lock.lock()
        guard generation == tickerGeneration,
              var nowPlaying = latest, nowPlaying.isPlaying else { lock.unlock(); return }
        nowPlaying.position += tickInterval
        if let duration = nowPlaying.duration, nowPlaying.position > duration {
            nowPlaying.position = duration
        }
        latest = nowPlaying
        continuation.yield(nowPlaying)
        lock.unlock()
    }

    private func finishFromEOF() {
        lock.lock()
        let ticker = tickerTask
        tickerTask = nil
        lock.unlock()
        ticker?.cancel()
        continuation.finish()
    }
}
