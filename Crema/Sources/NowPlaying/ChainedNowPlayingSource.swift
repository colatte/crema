import Foundation
import os

/// Composite NowPlaying source implementing the fallback chain (adapter → JXA →
/// off) behind the same NowPlayingSource protocol, so the Coordinator consumes
/// it unchanged. Self-healing: when the active source's stream finishes (its
/// process died / EOF), the chain re-evaluates availability and re-selects —
/// it never sits dead lying about availability. When nothing is available it
/// retries on an interval, so a recovered adapter is picked back up.
///
/// It also preempts: while a lower-priority source is active it probes the
/// preferred one periodically and, when it recovers, promotes at the next quiet
/// boundary — never mid-track (docs/DECISIONS.md: promotion-quiet-boundary).
/// Every source death — failover, total outage, or a deliberate promotion —
/// fires `onActiveSourceEnded` so the consumer drops the ghost snapshot rather
/// than resurrect dead media (docs/DECISIONS.md: ghost-discard).
final class ChainedNowPlayingSource: NowPlayingSource, StoppableSource, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let candidates: [NowPlayingCandidate]
    private let clock: any SleepClock
    private let retryInterval: Double
    /// How often to re-probe the preferred candidate while a lower-priority
    /// source is active. Re-promotion is not urgent, so this is coarse — the cost
    /// (a probe spawn with the child-process timeout) stays trivial.
    private let promotionProbeInterval: Double
    /// Reports whether a source is currently active (false = feature off), so
    /// the menu can signal the degraded state.
    private let onActiveChange: (@Sendable (Bool) -> Void)?
    private let lock = NSLock()
    private let logger = Logger.crema("NowPlaying")
    private var activeSource: (any NowPlayingSource)?
    private var activeChannel: (any NowPlayingCommandChannel)?
    private var controlTask: Task<Void, Never>?
    /// Background probe watching for the preferred candidate to recover while a
    /// lower-priority source is active; nil when the top-priority source runs.
    private var promotionProbeTask: Task<Void, Never>?
    /// Set by the probe when the preferred candidate is available again; the
    /// forwarding loop cuts over at the next quiet boundary.
    private var armedPromotion = false
    /// Whether the active source has yielded anything since selection — a source
    /// that has stayed silent is promoted immediately (boundary c), since it
    /// would never reach the in-loop boundary check.
    private var hasEmittedSinceSelect = false
    /// Fired (off-main) when the active source's forwarding ends — its process
    /// died (failover/outage) or a promotion cut it over. The last snapshot the
    /// consumer holds is a ghost; this is the signal to drop it
    /// (docs/DECISIONS.md: ghost-discard).
    /// Settable post-construction because the Coordinator it feeds is built
    /// after the chain (AppCore wires it once both exist).
    private var _onActiveSourceEnded: (@Sendable () -> Void)?

    init(
        candidates: [NowPlayingCandidate],
        clock: any SleepClock = ContinuousSleepClock(),
        retryInterval: Double = 2,
        promotionProbeInterval: Double = 30,
        onActiveChange: (@Sendable (Bool) -> Void)? = nil,
        onActiveSourceEnded: (@Sendable () -> Void)? = nil
    ) {
        var continuation: AsyncStream<NowPlaying>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(16)) { continuation = $0 }
        self.continuation = continuation
        self.candidates = candidates
        self.clock = clock
        self.retryInterval = retryInterval
        self.promotionProbeInterval = promotionProbeInterval
        self.onActiveChange = onActiveChange
        _onActiveSourceEnded = onActiveSourceEnded

        controlTask = Task { [weak self] in await self?.run() }
        continuation.onTermination = { [weak self] _ in self?.stop() }
    }

    deinit {
        controlTask?.cancel()
        lock.lock(); let probe = promotionProbeTask; promotionProbeTask = nil; lock.unlock()
        probe?.cancel()
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

    /// Wires the ghost-discard seam after construction. Used by AppCore, which
    /// builds the Coordinator (the handler's target) after the chain.
    func setActiveSourceEndedHandler(_ handler: @escaping @Sendable () -> Void) {
        lock.lock(); _onActiveSourceEnded = handler; lock.unlock()
    }

    func stop() {
        controlTask?.cancel()
        lock.lock()
        let active = activeSource
        let probe = promotionProbeTask
        activeSource = nil
        activeChannel = nil
        promotionProbeTask = nil
        lock.unlock()
        probe?.cancel()
        // Stop the active source synchronously so its process dies on quit
        // (deinit would be too late).
        (active as? StoppableSource)?.stop()
        continuation.finish()
    }

    private func run() async {
        while !Task.isCancelled {
            guard let selection = await selectCandidate() else {
                onActiveChange?(false)
                do { try await clock.sleep(for: retryInterval) } catch { break }
                continue
            }
            let source = selection.candidate.makeSource()
            // stop() may have run during the (async) probe; don't adopt a
            // freshly-spawned source that would then escape teardown.
            if Task.isCancelled {
                (source as? StoppableSource)?.stop()
                break
            }
            lock.withLock {
                activeSource = source
                activeChannel = selection.candidate.commandChannel
                hasEmittedSinceSelect = false
                armedPromotion = false
            }
            onActiveChange?(true)
            let name = selection.candidate.label.isEmpty
                ? "#\(selection.index)" : selection.candidate.label
            logger.info("now-playing chain selected \(name, privacy: .public) (priority \(selection.index, privacy: .public))")

            let promoted = await forwardUpdates(from: source, activeIndex: selection.index)
            if promoted {
                logger.notice("now-playing source \(name, privacy: .public) promoted away at a quiet boundary — cutting over to the preferred candidate")
            } else {
                logger.notice("now-playing source \(name, privacy: .public) ended (process death or outage) — re-selecting")
            }

            // The active source ended — its process died (failover/outage) or a
            // deliberate promotion broke the loop. Its last snapshot is a ghost:
            // signal the consumer to drop it (docs/DECISIONS.md: ghost-discard);
            // the next selected source rebuilds the state from its own snapshots.
            // Distinct from the older pinned-latent behavior, where a mid-chain
            // failover left that ghost armed until quit.
            fireActiveSourceEnded()

            // Backoff before re-selecting: avoids a spawn spin when a source
            // flaps (selected but its stream ends at once) or none is available,
            // and it is the retry that picks a recovered adapter back up.
            do { try await clock.sleep(for: retryInterval) } catch { break }
        }
        continuation.finish()
    }

    /// Forwards the active source's snapshots to the outer stream until it ends.
    /// While a higher-priority candidate exists (`activeIndex > 0`) a background
    /// probe watches for it to recover and arms a promotion; an armed promotion
    /// cuts over only at a quiet boundary — never mid-track
    /// (docs/DECISIONS.md: promotion-quiet-boundary). Returns whether a
    /// promotion (not the source's own death) ended the forwarding, so the
    /// caller can log the two exits distinctly.
    private func forwardUpdates(from source: any NowPlayingSource, activeIndex: Int) async -> Bool {
        let probe = activeIndex > 0 ? startPromotionProbe(activeIndex: activeIndex) : nil
        lock.withLock { promotionProbeTask = probe }

        var previous: NowPlaying?
        for await nowPlaying in source.updates {
            let armed = lock.withLock {
                hasEmittedSinceSelect = true
                return armedPromotion
            }
            if armed, PromotionBoundary.isQuiet(nowPlaying, previous: previous) {
                break // promote at this quiet boundary; drop the boundary snapshot
            }
            continuation.yield(nowPlaying)
            previous = nowPlaying
        }

        let (probeToCancel, promoted) = lock.withLock {
            let drained = (promotionProbeTask, armedPromotion)
            promotionProbeTask = nil
            activeSource = nil
            activeChannel = nil
            armedPromotion = false
            return drained
        }
        probeToCancel?.cancel()
        // A promotion broke the loop without the source finishing on its own —
        // stop its process so no orphan survives (idempotent if it already
        // ended by EOF).
        if promoted { (source as? StoppableSource)?.stop() }
        return promoted
    }

    /// Probes the preferred candidate on an interval; when it recovers, arms a
    /// promotion and returns (the forwarding loop, or a forced stop for a silent
    /// source, does the cutover).
    private func startPromotionProbe(activeIndex: Int) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do { try await self.clock.sleep(for: self.promotionProbeInterval) } catch { return }
                guard await self.preferredCandidateAvailable(above: activeIndex) else { continue }
                self.armPromotion()
                return
            }
        }
    }

    /// True when any candidate higher-priority than the active one can run now.
    private func preferredCandidateAvailable(above activeIndex: Int) async -> Bool {
        for candidate in candidates.prefix(activeIndex) where await candidate.isAvailable() {
            return true
        }
        return false
    }

    /// Arms a promotion. A source mid-playback keeps the flag and cuts over on
    /// its next quiet boundary; one that has emitted nothing since selection
    /// (boundary c) would never reach the in-loop check, so force its cutover
    /// now by stopping it.
    private func armPromotion() {
        lock.lock()
        guard activeSource != nil else { lock.unlock(); return }
        armedPromotion = true
        let silent = !hasEmittedSinceSelect
        let source = activeSource
        lock.unlock()
        if silent { (source as? StoppableSource)?.stop() }
    }

    private func fireActiveSourceEnded() {
        lock.lock(); let handler = _onActiveSourceEnded; lock.unlock()
        handler?()
    }

    private func selectCandidate() async -> (candidate: NowPlayingCandidate, index: Int)? {
        for (index, candidate) in candidates.enumerated() where await candidate.isAvailable() {
            return (candidate, index)
        }
        return nil
    }
}
