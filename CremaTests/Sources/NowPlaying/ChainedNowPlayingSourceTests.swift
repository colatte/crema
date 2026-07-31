// Every case shares the one chain harness; the file crossed the ceiling when the
// cancelled-probe negative landed, and splitting the suite would splinter it.
// swiftlint:disable file_length
import Foundation
import Testing
@testable import Crema

/// The composite chain over mock sources: priority selection, and the
/// self-heal where the active source finishing triggers a re-selection.
struct ChainedNowPlayingSourceTests {

    private func track(_ title: String, playing: Bool = true) -> NowPlaying {
        NowPlaying(title: title, isPlaying: playing, position: 0, duration: 100)
    }

    @Test func forwardsTheFirstAvailableCandidate() async {
        let adapter = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { true }, makeSource: { adapter }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock()
        )
        let iterator = BoundedStreamIterator(chain.updates)

        adapter.emit(track("A"))
        #expect(await iterator.next() == track("A"))
    }

    @Test func noteSeekReachesTheActiveSource() async {
        let adapter = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { true }, makeSource: { adapter }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock()
        )
        let iterator = BoundedStreamIterator(chain.updates)
        adapter.emit(track("A"))
        _ = await iterator.next()   // selection settled: the adapter is active

        chain.noteSeek(to: 55)
        #expect(adapter.seeks == [55])
    }

    @Test func fallsToTheSecondCandidateWhenTheFirstIsUnavailable() async {
        let jxa = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { false }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel()),
                .init(isAvailable: { true }, makeSource: { jxa }, commandChannel: MockCommandChannel()),
            ],
            clock: TestSleepClock()
        )
        let iterator = BoundedStreamIterator(chain.updates)

        jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))
    }

    @Test func reselectsWhenTheActiveSourceFinishes() async {
        let adapter = MockNowPlayingSource()
        let jxa = MockNowPlayingSource()
        let adapterUp = Flag()
        adapterUp.value = true
        let clock = TestSleepClock()

        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { adapterUp.value }, makeSource: { adapter }, commandChannel: MockCommandChannel()),
                .init(isAvailable: { true }, makeSource: { jxa }, commandChannel: MockCommandChannel()),
            ],
            clock: clock
        )
        let iterator = BoundedStreamIterator(chain.updates)

        adapter.emit(track("A"))
        #expect(await iterator.next() == track("A"))

        // Adapter process dies and it is no longer available: the chain must
        // re-select and fall to JXA — not stay dead lying about availability.
        adapterUp.value = false
        adapter.finish()

        // Chain parks on the re-selection backoff; advance past it.
        await clock.waitForSleep()
        clock.advance()

        jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))
    }

    @Test func failoverDoesNotEmitAStopOnTheOuterStream_pinnedLatentS6() async {
        // Fence (docs/DECISIONS.md: ghost-discard): a mid-chain inner-stream
        // failover surfaces NO synthetic "stopped" snapshot on the OUTER stream —
        // the chain never fakes a NowPlaying to represent "no media". The ghost is dropped
        // out-of-band instead, via the onActiveSourceEnded callback (see
        // firesActiveSourceEndedWhenTheActiveSourceDies); this test is
        // constructed WITHOUT that handler, so it pins the stream contract in
        // isolation: the domain stream carries only real snapshots. A failure
        // here means someone started injecting a synthetic stop on the stream —
        // decide that consciously, don't let it drift.
        let adapter = MockNowPlayingSource()
        let adapterUp = Flag()
        adapterUp.value = true
        let clock = TestSleepClock()

        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { adapterUp.value }, makeSource: { adapter }, commandChannel: MockCommandChannel()),
                // JXA is blind to the browser source (unavailable): once the
                // adapter dies, no candidate can represent the "playing" media.
                .init(isAvailable: { false }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel()),
            ],
            clock: clock
        )

        let collector = SnapshotCollector()
        let consumer = Task { for await value in chain.updates { collector.append(value) } }

        adapter.emit(track("A"))
        #expect(await eventuallyOffActor { collector.all.last == track("A") })

        // Adapter process dies mid-playback and is no longer available.
        adapterUp.value = false
        adapter.finish()

        // Wait until the failover has fully run: the inner loop exited,
        // activeSource=nil, re-selection found nothing, and the chain parked on
        // the retry backoff. That backoff sleep is the fence point.
        await clock.waitForSleep()
        // Give the outer stream every chance to (wrongly) emit a stop snapshot, and
        // return the moment one appears. Wall clock rather than a yield count: the
        // emission would come from the chain's own task, and yields here buy no time
        // on the thread running it.
        _ = await footprintAppears { collector.all.count > 1 }

        let all = collector.all
        // The ghost: the only outer emission is the still-playing track A; no
        // not-playing ("stopped") snapshot was ever produced on the failover.
        #expect(all == [track("A")])
        // Key-path form breaks the #expect macro expansion (spurious "call can
        // throw"), so the closure stays and the result is hoisted out of the macro.
        // swiftformat:disable:next preferKeyPath
        let allPlaying = all.allSatisfy { $0.isPlaying }
        #expect(allPlaying)

        consumer.cancel()
        chain.stop()
    }

    // MARK: - Preemption back to a recovered preferred source

    /// A chain stuck on the JXA fallback with the adapter recovering on demand
    /// (flip `adapterUp`). Distinct command channels stand in for the two
    /// backends so the active one is observable through activeCommandChannel().
    private struct FallbackFixture {
        let chain: ChainedNowPlayingSource
        let adapter = MockNowPlayingSource()
        let jxa = MockNowPlayingSource()
        let adapterChannel = MockCommandChannel()
        let jxaChannel = MockCommandChannel()
        let adapterUp = Flag()   // adapter starts down → JXA is selected
        let clock = TestSleepClock()

        init() {
            chain = ChainedNowPlayingSource(
                candidates: [
                    .init(
                        isAvailable: { [adapterUp] in adapterUp.value },
                        makeSource: { [adapter] in adapter },
                        commandChannel: adapterChannel
                    ),
                    .init(isAvailable: { true }, makeSource: { [jxa] in jxa }, commandChannel: jxaChannel),
                ],
                clock: clock,
                promotionProbeInterval: 30
            )
        }
    }

    /// Fires the 30 s promotion probe and waits until it has ARMED, so a following
    /// boundary emit cuts over instead of racing the arm. The wait is on the arm
    /// itself and never on the availability check that precedes it: that check
    /// answers on the probe's own thread a few instructions earlier, so a test
    /// fenced on it can still emit its boundary first — the snapshot is then
    /// forwarded, no boundary is left, and the cutover being asserted never comes.
    /// Bounded by wall clock like every wait here; expiry fails on this line.
    private func armProbe(_ fixture: FallbackFixture) async {
        await fixture.clock.waitForSleep(delay: 30)
        fixture.adapterUp.value = true
        fixture.clock.advance(delay: 30)
        #expect(await eventuallyOffActor { fixture.chain.promotionIsArmed },
                "the promotion probe never armed")
    }

    @Test func promotesToARecoveredAdapterOnlyAtAPauseBoundary() async {
        let fixture = FallbackFixture()
        let iterator = BoundedStreamIterator(fixture.chain.updates)

        fixture.jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.jxaChannel)

        // The adapter recovers; the 30 s probe arms a promotion.
        await armProbe(fixture)

        // Mid-track (same track, still playing) is not a boundary: it HOLDS —
        // the snapshot is forwarded by JXA, no cutover.
        fixture.jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.jxaChannel)

        // A pause is a quiet boundary: promote. The paused snapshot is dropped
        // (a cutover, not forwarded); the adapter's snapshot surfaces next. That
        // the boundary DOES promote proves the arming above took effect.
        fixture.jxa.emit(track("J", playing: false))
        fixture.adapter.emit(track("A"))
        await fixture.clock.waitForSleep(delay: 2)   // backoff after the promotion break
        fixture.clock.advance(delay: 2)
        #expect(await iterator.next() == track("A"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.adapterChannel)

        fixture.chain.stop()
    }

    @Test func promotesAtATrackChangeBoundary() async {
        let fixture = FallbackFixture()
        let iterator = BoundedStreamIterator(fixture.chain.updates)

        fixture.jxa.emit(track("J1"))
        #expect(await iterator.next() == track("J1"))

        await armProbe(fixture)

        // A different track (still playing) IS a quiet boundary — the surface is
        // already changing content, so the cutover rides along.
        fixture.jxa.emit(track("J2"))
        fixture.adapter.emit(track("A"))
        await fixture.clock.waitForSleep(delay: 2)
        fixture.clock.advance(delay: 2)
        #expect(await iterator.next() == track("A"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.adapterChannel)

        fixture.chain.stop()
    }

    @Test func promotesImmediatelyWhenTheActiveSourceHasStayedSilent() async {
        // Boundary (c): a source that has emitted nothing since selection is
        // promoted at once — it would never reach the in-loop boundary check.
        let fixture = FallbackFixture()
        let iterator = BoundedStreamIterator(fixture.chain.updates)

        // JXA is selected (adapter down) but stays silent — no track emitted.
        // The probe parking confirms JXA is the active source.
        await fixture.clock.waitForSleep(delay: 30)
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.jxaChannel)

        // The adapter recovers; the probe arms and, seeing JXA silent, forces
        // the cutover without waiting for a boundary that will never come.
        fixture.adapterUp.value = true
        fixture.clock.advance(delay: 30)

        fixture.adapter.emit(track("A"))
        await fixture.clock.waitForSleep(delay: 2)
        fixture.clock.advance(delay: 2)
        #expect(await iterator.next() == track("A"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.adapterChannel)

        fixture.chain.stop()
    }

    @Test func doesNotPromoteWhenTheProbeFindsThePreferredStillUnavailable() async {
        // Negative of the promotion gate: the 30 s probe fires while the adapter
        // is still down, so preferredCandidateAvailable rejects it and nothing arms
        // — a following quiet boundary must NOT cut over. Guards against a probe
        // that promotes to a dead preferred source (the gate armed unconditionally).
        let fixture = FallbackFixture()
        let iterator = BoundedStreamIterator(fixture.chain.updates)

        fixture.jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.jxaChannel)

        // Fire the probe with the adapter still down: the gate rejects it and the
        // probe re-parks on the next interval without arming (adapterUp stays false).
        await fixture.clock.waitForSleep(delay: 30)
        fixture.clock.advance(delay: 30)
        await fixture.clock.waitForSleep(delay: 30)

        // A pause is a quiet boundary — but with nothing armed it is forwarded by
        // JXA, not consumed as a cutover, and the active channel stays JXA.
        fixture.jxa.emit(track("J", playing: false))
        #expect(await iterator.next() == track("J", playing: false))
        #expect((fixture.chain.activeCommandChannel() as? MockCommandChannel) === fixture.jxaChannel)

        fixture.chain.stop()
    }

    /// A short wall-clock window for a NEGATIVE. It returns the moment `footprint`
    /// appears, so a regression fails fast; otherwise it costs the window. Kept off
    /// the suite's 5 s budget on purpose — that budget exists so a POSITIVE wait
    /// never expires early, while here an early expiry can only pass wrongly, never
    /// fail wrongly, and the window it has to outlast is one lock acquisition on a
    /// thread that is already running. Wall clock, not a yield count: yields buy
    /// nothing against work on another thread.
    private func footprintAppears(within window: Duration = .milliseconds(200), _ footprint: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: window)
        while clock.now < deadline {
            if footprint() { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return footprint()
    }

    @Test func aProbeAnsweringAfterItsForwardingEndedArmsNothing() async {
        // The probe's availability answer can outlive the forwarding that started it
        // — in production it is a child-process spawn under a deadline, so the cancel
        // at the exit reaches a task already past the point where cancellation is
        // seen. Arming then fires at whatever was selected next: here the recovered
        // adapter at priority 0, which has nothing above it to promote to and, silent
        // since selection, is stopped outright — a fresh source killed by a probe
        // that never watched it.
        let adapter = MockNowPlayingSource()
        let jxa = MockNowPlayingSource()
        let adapterChannel = MockCommandChannel()
        let adapterUp = Flag()
        let probeAsking = Flag()
        let probeAnswered = Flag()
        let releaseProbe = Flag()
        let ended = Flag()
        let clock = TestSleepClock()

        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(
                    isAvailable: {
                        guard adapterUp.value else { return false }
                        // Only the first ask stalls — the probe's, held until the next
                        // selection is in place, which is how a real one outlives the
                        // source it was watching. Every later ask (the re-selection's)
                        // answers at once, or the chain could never get past it.
                        guard !probeAsking.value else { return true }
                        probeAsking.value = true
                        _ = await eventuallyOffActor { releaseProbe.value }
                        probeAnswered.value = true
                        return true
                    },
                    makeSource: { adapter },
                    commandChannel: adapterChannel
                ),
                .init(isAvailable: { true }, makeSource: { jxa }, commandChannel: MockCommandChannel()),
            ],
            clock: clock,
            promotionProbeInterval: 30,
            onActiveSourceEnded: { ended.value = true }
        )
        let iterator = BoundedStreamIterator(chain.updates)

        jxa.emit(track("J"))
        #expect(await iterator.next() == track("J"))

        // The 30 s probe fires with the adapter recovered, and stalls inside the ask.
        await clock.waitForSleep(delay: 30)
        adapterUp.value = true
        clock.advance(delay: 30)
        #expect(await eventuallyOffActor { probeAsking.value })

        // JXA dies while that ask is still out: the forwarding ends, the probe is
        // cancelled, and after the backoff the chain selects the recovered adapter.
        jxa.finish()
        await clock.waitForSleep(delay: 2)
        clock.advance(delay: 2)
        let selectedTheAdapter = await eventuallyOffActor {
            (chain.activeCommandChannel() as? MockCommandChannel) === adapterChannel
        }
        #expect(selectedTheAdapter, "the chain never selected the recovered adapter")
        // The seam fired for JXA's death; from here on, a fire IS the defect.
        ended.value = false

        releaseProbe.value = true
        #expect(await eventuallyOffActor { probeAnswered.value })
        let killedTheFreshSelection = await footprintAppears { ended.value || chain.promotionIsArmed }
        #expect(!killedTheFreshSelection,
                "an answer that outlived its forwarding armed a promotion at the source selected after it")

        chain.stop()
    }

    // MARK: - S6: the active source ending fires the ghost-discard seam

    @Test func firesActiveSourceEndedWhenTheActiveSourceDies() async {
        let adapter = MockNowPlayingSource()
        let ended = Flag()
        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { true }, makeSource: { adapter }, commandChannel: MockCommandChannel()),
            ],
            clock: TestSleepClock(),
            onActiveSourceEnded: { ended.value = true }
        )
        let iterator = BoundedStreamIterator(chain.updates)
        adapter.emit(track("A"))
        #expect(await iterator.next() == track("A"))

        // The source dies without the OUTER stream finishing (retry keeps it
        // alive): the seam must fire so the consumer drops the ghost.
        adapter.finish()
        #expect(await eventuallyOffActor { ended.value })

        chain.stop()
    }

    @Test func firesActiveSourceEndedOnAPromotion() async {
        // The deliberate promotion uses the same ghost-discard seam as a
        // failover — no zombie snapshot survives the cutover. A silent JXA is
        // promoted deterministically (boundary c: the probe forces the stop),
        // which ends the source and fires the seam.
        let adapter = MockNowPlayingSource()
        let jxa = MockNowPlayingSource()
        let adapterUp = Flag()
        let ended = Flag()
        let clock = TestSleepClock()
        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { adapterUp.value }, makeSource: { adapter }, commandChannel: MockCommandChannel()),
                .init(isAvailable: { true }, makeSource: { jxa }, commandChannel: MockCommandChannel()),
            ],
            clock: clock,
            promotionProbeInterval: 30,
            onActiveSourceEnded: { ended.value = true }
        )
        _ = chain.updates.makeAsyncIterator()

        // JXA is selected (adapter down) and stays silent. The probe parking
        // confirms it is the active source.
        await clock.waitForSleep(delay: 30)

        // The adapter recovers; the probe arms and forces the silent source's
        // cutover, which fires the seam. Advance inside the poll (the OSD
        // suites' load-robust handshake): the probe's park can lag under the
        // parallel suite, and an advance with no sleeper is a no-op — repeated
        // advances are idempotent.
        adapterUp.value = true
        #expect(await eventuallyOffActor {
            clock.advance(delay: 30)
            return ended.value
        })

        chain.stop()
    }

    @Test func isAvailableWhenAnyCandidateIs() async {
        let none = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { false }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock()
        )
        #expect(await !none.isAvailable())

        let some = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { false }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel()),
                .init(isAvailable: { true }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel()),
            ],
            clock: TestSleepClock()
        )
        #expect(await some.isAvailable())
    }

    @Test func exposesTheActiveCandidatesCommandChannel() async {
        let adapterChannel = MockCommandChannel()
        let jxaChannel = MockCommandChannel()
        let adapter = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [
                .init(isAvailable: { false }, makeSource: { MockNowPlayingSource() }, commandChannel: jxaChannel),
                .init(isAvailable: { true }, makeSource: { adapter }, commandChannel: adapterChannel),
            ],
            clock: TestSleepClock()
        )
        let iterator = BoundedStreamIterator(chain.updates)

        adapter.emit(track("A"))
        _ = await iterator.next()   // selection has happened

        #expect((chain.activeCommandChannel() as? MockCommandChannel) === adapterChannel)
    }

    @Test func reportsActiveStatusChanges() async {
        let flips = Flag()
        let active = Flag()
        let chain = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { true }, makeSource: { MockNowPlayingSource() }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock(),
            onActiveChange: { isActive in flips.value = true; active.value = isActive }
        )
        _ = chain
        #expect(await eventuallyOffActor { flips.value && active.value })
    }
}

/// Lock-protected sink for the outer stream — the consumer Task appends off the
/// main actor while the test asserts, so a negative ("no stop emitted") can be
/// pinned safely.
private final class SnapshotCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var _all: [NowPlaying] = []
    var all: [NowPlaying] { lock.withLock { _all } }
    func append(_ value: NowPlaying) { lock.withLock { _all.append(value) } }
}
