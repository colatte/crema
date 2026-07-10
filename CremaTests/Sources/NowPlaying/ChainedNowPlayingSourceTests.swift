import Foundation
import Testing
@testable import Crema

/// The composite chain over mock sources: priority selection, and the
/// self-heal where the active source finishing triggers a re-selection.
struct ChainedNowPlayingSourceTests {

    private func track(_ title: String) -> NowPlaying {
        NowPlaying(title: title, isPlaying: true, position: 0, duration: 100)
    }

    @Test func forwardsTheFirstAvailableCandidate() async {
        let adapter = MockNowPlayingSource()
        let chain = ChainedNowPlayingSource(
            candidates: [.init(isAvailable: { true }, makeSource: { adapter }, commandChannel: MockCommandChannel())],
            clock: TestSleepClock()
        )
        var iterator = chain.updates.makeAsyncIterator()

        adapter.emit(track("A"))
        #expect(await iterator.next() == track("A"))
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
        var iterator = chain.updates.makeAsyncIterator()

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
        var iterator = chain.updates.makeAsyncIterator()

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
        // Pinned-latent fence (CONTRACTS-AUDIT S6): a mid-chain inner-stream
        // failover surfaces NO "stopped" snapshot on the OUTER stream. When the
        // adapter dies mid-playback and no other candidate can represent the
        // media, the last live snapshot simply stays put — so the Coordinator
        // keeps the ghost with mediaActive=true and click-invoke armed. This
        // pins that CURRENT behavior: a failure here means someone changed the
        // ghost contract (started surfacing a stop on failover) — decide that
        // consciously, don't let it drift.
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
        #expect(await pollUntil { collector.all.last == track("A") })

        // Adapter process dies mid-playback and is no longer available.
        adapterUp.value = false
        adapter.finish()

        // Wait until the failover has fully run: the inner loop exited,
        // activeSource=nil, re-selection found nothing, and the chain parked on
        // the retry backoff. That backoff sleep is the fence point.
        await clock.waitForSleep()
        // Give the outer stream every chance to (wrongly) emit a stop snapshot.
        for _ in 0..<200 { await Task.yield() }

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
        var iterator = chain.updates.makeAsyncIterator()

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
        #expect(await pollUntil { flips.value && active.value })
    }

    private func pollUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<2000 {
            if condition() { return true }
            await Task.yield()
        }
        return condition()
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
