import Foundation
import os

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
    /// A user seek awaiting the player's echo (noteSeek). While armed, the
    /// reconciliation obeys an anchor near the target (even where the plain
    /// rules would hold it — the sub-tolerance backward step, the paused
    /// freeze) and HOLDS any other anchor as a stale pre-seek echo. Three
    /// honest exits, so the hold is always bounded: confirmation (anchor ≈
    /// target), track change, or the anchor budget running out (the echo
    /// never came — plain rules resume); a failed command also rolls it back
    /// (noteSeekFailed, restoring the pre-seek line).
    private var pendingSeek: (target: Double, anchorsLeft: Int, preSeekPosition: Double)?
    /// The position the ticker extrapolates FROM: a known-good position, the
    /// instant it was true, and the rate it advances at. Every tick recomputes
    /// `position + age × rate` instead of adding a step, so a late, coalesced
    /// or dropped tick costs nothing — the clock, not the tick count, is what
    /// says how much playback happened (docs/DECISIONS.md: sample-dont-integrate).
    private var anchor: (position: Double, instant: Date, rate: Double)?
    /// How many real anchors may arrive without confirming before the hint
    /// expires. Bounds the hold the same way the Coordinator's grace window
    /// bounds the display override.
    private static let pendingSeekAnchorBudget = 3
    private let logger = Logger.crema("NowPlaying")

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

    /// The user sought (the scrubber's release): re-anchor `latest` to the
    /// target so the ticker counts from where the user landed instead of the
    /// pre-seek position — without this, the 1 Hz tick keeps emitting old+1s
    /// until the player's echo arrives, which is the "rewinds then corrects"
    /// symptom. The generation bump invalidates in-flight ticks and the ticker
    /// restarts on the fresh anchor. No yield: the Coordinator already shows
    /// the target optimistically; echoing it here would be a duplicate.
    func noteSeek(to seconds: Double) {
        lock.lock()
        guard var nowPlaying = latest else { lock.unlock(); return }
        let floored = max(0, seconds)
        let target = nowPlaying.duration.map { min(floored, $0) } ?? floored
        pendingSeek = (target, Self.pendingSeekAnchorBudget, nowPlaying.position)
        nowPlaying.position = target
        anchor = (target, now(), anchor?.rate ?? 1)
        latest = nowPlaying
        tickerGeneration += 1
        let generation = tickerGeneration
        let playing = nowPlaying.isPlaying
        lock.unlock()
        restartTicker(playing: playing, generation: generation)
    }

    /// The seek command failed or never reached a player: restore the
    /// pre-seek line — the honest position is where the player kept playing
    /// from, not the target the re-anchor fabricated. The restored anchor is
    /// stale by the command's flight time (bounded by its deadline); the next
    /// real payload trues it up.
    func noteSeekFailed() {
        lock.lock()
        guard let pending = pendingSeek else { lock.unlock(); return }
        pendingSeek = nil
        guard var nowPlaying = latest else { lock.unlock(); return }
        nowPlaying.position = pending.preSeekPosition
        anchor = (pending.preSeekPosition, now(), anchor?.rate ?? 1)
        latest = nowPlaying
        tickerGeneration += 1
        let generation = tickerGeneration
        let playing = nowPlaying.isPlaying
        continuation.yield(nowPlaying)
        lock.unlock()
        restartTicker(playing: playing, generation: generation)
    }

    private func consume(_ line: String) {
        let deliveredAt = now()
        guard let snapshot = AdapterPayloadTranslation.snapshot(fromLine: line, at: deliveredAt) else {
            markNothingPlaying()
            return
        }
        var nowPlaying = snapshot.nowPlaying
        lock.lock()
        let rawAnchor = nowPlaying.position
        let shownBefore = latest?.position
        nowPlaying.position = PositionReconciliation.position(
            for: nowPlaying, replacing: latest, pendingSeek: pendingSeek?.target
        )
        // Re-anchor only when the reconciliation ACCEPTED this payload's line.
        // When it holds the previous value (paused freeze, jitter, stale echo
        // under a pending seek), re-anchoring at that held value with `now`
        // would throw away the time already elapsed under the old anchor.
        if nowPlaying.position == rawAnchor {
            if let shownBefore, nowPlaying.isPlaying {
                // The drift the anchor just corrected: the discriminating line
                // for the field report about the bar losing sync. On a healthy
                // clock this is player rounding (sub-second).
                logger.debug("""
                position re-anchored: shown \(shownBefore, privacy: .public)s → \
                anchor \(rawAnchor, privacy: .public)s \
                (drift \(rawAnchor - shownBefore, privacy: .public)s)
                """)
            }
            anchor = (rawAnchor, deliveredAt, snapshot.rate)
        }
        // The hint's exits, in order: confirmation (the RAW anchor near the
        // target — within tolerance, stale and echo are numerically the same
        // thing), track change, or the anchor budget running out (the echo
        // never came; plain rules resume, bounding the stale-hold above).
        if let pending = pendingSeek {
            let identityChanged = latest?.title != nowPlaying.title || latest?.artist != nowPlaying.artist
            let confirmed = abs(rawAnchor - pending.target) <= PositionReconciliation.seekConfirmTolerance
            if identityChanged || confirmed || pending.anchorsLeft <= 1 {
                pendingSeek = nil
            } else {
                pendingSeek = (pending.target, pending.anchorsLeft - 1, pending.preSeekPosition)
            }
        }
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

    /// The install only lands while its generation is still current: consume
    /// (serial, on the consumer task) and noteSeek/noteSeekFailed (MainActor)
    /// can race here, and an out-of-order install would leave a ticker whose
    /// generation never matches — every tick a no-op, the position frozen
    /// until the next payload. The same guard retires the stop() race: stop
    /// cancels the ticker it sees, and a late installer either loses the
    /// generation check or its orphan is reaped by finishFromEOF (stop
    /// cancelled the consumer, so its loop exits there) — that ticker-cancel
    /// is not redundant with stop()'s; removing it would leak a
    /// self-retaining ticker.
    private func restartTicker(playing: Bool, generation: Int) {
        let newTicker = playing ? Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.clock.sleep(for: self.tickInterval) } catch { return }
                self.tick(ifCurrent: generation)
            }
        } : nil
        lock.lock()
        guard generation == tickerGeneration else {
            lock.unlock()
            newTicker?.cancel()
            return
        }
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
        // Sampled, not accumulated: the position is whatever the anchor implies
        // at this instant. A tick that arrives late (throttled app, coalesced
        // timer) lands on the true position instead of adding a fixed second,
        // and a tick that never arrives costs nothing — which is what keeps the
        // bar in sync through a whole track, since players re-anchor only on
        // state changes. (docs/DECISIONS.md: sample-dont-integrate)
        guard let anchor else { lock.unlock(); return }
        // `now` is the WALL clock, which an NTP step correction or a manual time
        // change moves while the ticker's own clock keeps running — and sampling
        // means the bar follows it. The floor is what stops a backward step from
        // UNDOING age already shown (anchor 10 s, ticked to 40 s, clock back
        // 30 s, sampled 10 s); a non-negative age never covered that, since it
        // only bounds the anchor's own instant. It floors the SHOWN line, never
        // a remembered maximum: every anchor write rewrites that line too (an
        // accepted payload, noteSeek, noteSeekFailed), so a legitimate backward
        // re-anchor lowers the floor with it instead of stranding the bar above
        // the truth. And the origin stays put rather than being re-anchored on
        // the backward edge: moving it makes the tick accumulate again, so clock
        // noise would ratchet the bar forward. The residual, accepted: after a
        // one-way step back the bar sits behind by the step until the next
        // payload — the same error the rewind left, minus the visible jump.
        let age = max(0, now().timeIntervalSince(anchor.instant))
        var sampled = anchor.position + age * anchor.rate
        // Forward playback only: a negative rate (a rewind scan, aged with the
        // same sign by the payload math) is the bar moving back honestly, and it
        // is the one case the non-negative age still decides — with the rate
        // negative, a backward clock would otherwise ADVANCE the bar.
        if anchor.rate > 0 {
            sampled = max(nowPlaying.position, sampled)
        }
        // Clamped last, so the end of the track outranks the floor.
        if let duration = nowPlaying.duration, sampled > duration {
            sampled = duration
        }
        nowPlaying.position = sampled
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
