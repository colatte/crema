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
