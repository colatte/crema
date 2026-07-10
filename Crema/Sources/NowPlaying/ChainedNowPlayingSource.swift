import Foundation

/// Composite NowPlaying source implementing the fallback chain (adapter → JXA →
/// off) behind the same NowPlayingSource protocol, so the Coordinator consumes
/// it unchanged. Self-healing: when the active source's stream finishes (its
/// process died / EOF), the chain re-evaluates availability and re-selects —
/// it never sits dead lying about availability. When nothing is available it
/// retries on an interval, so a recovered adapter is picked back up.
final class ChainedNowPlayingSource: NowPlayingSource, StoppableSource, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let candidates: [NowPlayingCandidate]
    private let clock: any SleepClock
    private let retryInterval: Double
    /// Reports whether a source is currently active (false = feature off), so
    /// the menu can signal the degraded state.
    private let onActiveChange: (@Sendable (Bool) -> Void)?
    private let lock = NSLock()
    private var activeSource: (any NowPlayingSource)?
    private var activeChannel: (any NowPlayingCommandChannel)?
    private var controlTask: Task<Void, Never>?

    init(
        candidates: [NowPlayingCandidate],
        clock: any SleepClock = ContinuousSleepClock(),
        retryInterval: Double = 2,
        onActiveChange: (@Sendable (Bool) -> Void)? = nil
    ) {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation = $0 }
        self.continuation = continuation
        self.candidates = candidates
        self.clock = clock
        self.retryInterval = retryInterval
        self.onActiveChange = onActiveChange

        controlTask = Task { [weak self] in await self?.run() }
        continuation.onTermination = { [weak self] _ in self?.stop() }
    }

    deinit {
        controlTask?.cancel()
        continuation.finish()
    }

    func isAvailable() async -> Bool {
        for candidate in candidates where await candidate.isAvailable() {
            return true
        }
        return false
    }

    /// The command channel of the active candidate — the RoutingNowPlayingController
    /// resolves this per command so writes follow the active backend.
    func activeCommandChannel() -> (any NowPlayingCommandChannel)? {
        lock.lock(); defer { lock.unlock() }
        return activeChannel
    }

    func stop() {
        controlTask?.cancel()
        lock.lock()
        let active = activeSource
        activeSource = nil
        activeChannel = nil
        lock.unlock()
        // Stop the active source synchronously so its process dies on quit
        // (deinit would be too late).
        (active as? StoppableSource)?.stop()
        continuation.finish()
    }

    private func run() async {
        while !Task.isCancelled {
            if let candidate = await selectCandidate() {
                let source = candidate.makeSource()
                // stop() may have run during the (async) probe; don't adopt a
                // freshly-spawned source that would then escape teardown.
                if Task.isCancelled {
                    (source as? StoppableSource)?.stop()
                    break
                }
                lock.lock()
                activeSource = source
                activeChannel = candidate.commandChannel
                lock.unlock()
                onActiveChange?(true)
                // Forward until the active source finishes (process death / EOF).
                for await nowPlaying in source.updates {
                    continuation.yield(nowPlaying)
                }
                // Pinned-latent (see CONTRACTS-AUDIT S6): a mid-chain failover
                // yields no "stopped" snapshot here — the last live snapshot
                // stays on the outer stream, so a re-select cannot drop a ghost.
                lock.lock(); activeSource = nil; activeChannel = nil; lock.unlock()
            } else {
                onActiveChange?(false)
            }
            // Backoff before re-selecting: avoids a spawn spin when a source
            // flaps (selected but its stream ends at once) or none is available,
            // and it is the retry that picks a recovered adapter back up.
            do { try await clock.sleep(for: retryInterval) } catch { break }
        }
        continuation.finish()
    }

    private func selectCandidate() async -> NowPlayingCandidate? {
        for candidate in candidates where await candidate.isAvailable() {
            return candidate
        }
        return nil
    }
}
