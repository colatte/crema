import Foundation
import Testing
@testable import Crema

// A couple of JSON fixtures below are single long lines by nature.
// swiftlint:disable line_length

/// The adapter source over fake lines + an injectable clock (no real
/// process): translation emitted, local position tick while playing, hide on
/// empty payload, and finish when the line stream ends (EOF → self-heal signal).
@MainActor
struct MediaRemoteAdapterNowPlayingSourceTests {

    private func line(title: String = "Breathe", position: Double, playing: Bool) -> String {
        #"{"type":"data","diff":false,"payload":{"title":"\#(title)","artist":"Pink Floyd","playing":\#(playing),"elapsedTime":\#(position),"duration":169.0}}"#
    }

    private var emptyLine: String {
        #"{"type":"data","diff":false,"payload":{}}"#
    }

    /// Wall clock the test drives, injected as the source's `now`. The ticker
    /// samples it (docs/DECISIONS.md: sample-dont-integrate), so a tick only
    /// moves the position if TIME moved — which is exactly the coupling the
    /// old `+1 per tick` assertions were missing.
    private final class TestWallClock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_000_000)
        var now: @Sendable () -> Date { { self.lock.withLock { self.date } } }
        func advance(_ seconds: Double) { lock.withLock { date = date.addingTimeInterval(seconds) } }
    }

    @Test func emitsTranslatedNowPlaying() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(lines: lines, availability: { true }, clock: TestSleepClock())
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))

        let first = await iterator.next()
        #expect(first?.title == "Breathe")
        #expect(first?.artist == "Pink Floyd")
        #expect(first?.position == 10)
        #expect(first?.isPlaying == true)
    }

    @Test func advancesPositionLocallyWhilePlaying() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)

        await clock.waitForSleep()
        wall.advance(1)
        clock.advance()
        let ticked = await iterator.next()
        #expect(ticked?.position == 11)
        #expect(ticked?.title == "Breathe")   // same track, position advanced
    }

    @Test func aLateTickLandsOnTheTruePositionInsteadOfOneSecond() async {
        // The field bug (docs/DECISIONS.md: sample-dont-integrate): a throttled
        // or coalesced tick used to add exactly one second no matter how long it
        // had really been, and since players re-anchor only on state changes,
        // the loss accumulated for the whole track.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)

        await clock.waitForSleep()
        wall.advance(3)                      // the tick arrives three seconds late
        clock.advance()
        #expect(await iterator.next()?.position == 13)
    }

    @Test func ticksAreIdempotentWithinTheSameInstant() async {
        // Two ticks and no time passing must not count twice — the tick reports
        // the clock, it does not accumulate.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)

        wall.advance(2)
        source.tick(ifCurrent: 1)
        source.tick(ifCurrent: 1)
        #expect(await iterator.next()?.position == 12)
        #expect(await iterator.next()?.position == 12)
    }

    @Test func aBackwardWallClockJumpFreezesInsteadOfRewinding() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)

        wall.advance(-30)                    // NTP correction, manual clock change
        source.tick(ifCurrent: 1)
        #expect(await iterator.next()?.position == 10)
    }

    @Test func theTickHonorsThePlaybackRate() async {
        // A podcast at 1.5×: the payload carries the rate and the anchor keeps
        // it, so a second of wall clock is 1.5 s of playback.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(#"{"type":"data","diff":false,"payload":{"title":"Breathe","artist":"Pink Floyd","playing":true,"elapsedTime":10.0,"duration":169.0,"playbackRate":1.5}}"#)
        #expect(await iterator.next()?.position == 10)

        wall.advance(2)
        source.tick(ifCurrent: 1)
        #expect(await iterator.next()?.position == 13)
    }

    @Test func noteSeekReanchorsTheTickerAndInvalidatesInFlightTicks() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))          // generation 1
        #expect(await iterator.next()?.position == 10)

        source.noteSeek(to: 120)                               // re-anchor, generation 2
        wall.advance(1)
        source.tick(ifCurrent: 1)                              // in-flight pre-seek tick: dropped
        source.tick(ifCurrent: 2)                              // the fresh ticker counts from the target
        #expect(await iterator.next()?.position == 121)
    }

    @Test func noteSeekBeyondTheDurationClampsToIt() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)

        source.noteSeek(to: 500)                               // fixture duration is 169
        source.tick(ifCurrent: 2)
        #expect(await iterator.next()?.position == 169)        // anchored and tick-clamped at the end
    }

    @Test func aPendingSeekEchoOvercomesTheJitterHold() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 100, playing: true))
        #expect(await iterator.next()?.position == 100)

        // Micro backward scrub: the player's echo lands a shade behind the
        // re-anchored target — a sub-tolerance regression the plain rules
        // would hold; the pending seek lets it land.
        source.noteSeek(to: 98.5)
        feed.yield(line(position: 98.2, playing: true))
        #expect(await iterator.next()?.position == 98.2)
    }

    @Test func aFailedSeekRestoresThePreSeekLine() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))          // generation 1
        #expect(await iterator.next()?.position == 10)

        source.noteSeek(to: 120)                               // generation 2
        source.noteSeekFailed()                                // generation 3, back to the pre-seek line
        #expect(await iterator.next()?.position == 10)
        wall.advance(1)
        source.tick(ifCurrent: 3)
        #expect(await iterator.next()?.position == 11)         // ticking from the restored anchor
    }

    @Test func theHintExpiresAfterItsAnchorBudget() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), tickInterval: 1
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 100, playing: true))
        #expect(await iterator.next()?.position == 100)
        source.noteSeek(to: 50)                                // backward seek; echo never comes

        // Three stale far anchors are held at the re-anchored line (the
        // budget), then the hint expires and the plain rules resume.
        for anchor in [101.0, 102.0, 103.0] {
            feed.yield(line(position: anchor, playing: true))
            #expect(await iterator.next()?.position == 50, "anchor \(anchor) should be held")
        }
        feed.yield(line(position: 104, playing: true))
        #expect(await iterator.next()?.position == 104)        // budget spent: stream rules
    }

    @Test func doesNotTickWhilePaused() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let source = MediaRemoteAdapterNowPlayingSource(lines: lines, availability: { true }, clock: clock)
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 5, playing: false))
        #expect(await iterator.next()?.isPlaying == false)

        await settle()
        #expect(clock.pendingSleeps == 0)   // no ticker parked while paused
    }

    @Test func emptyPayloadHidesByMarkingLastNotPlaying() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(lines: lines, availability: { true }, clock: TestSleepClock())
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.isPlaying == true)

        feed.yield(emptyLine)
        let hidden = await iterator.next()
        #expect(hidden?.isPlaying == false)
        #expect(hidden?.title == "Breathe")
    }

    @Test func aStaleAnchorOnPauseDoesNotRewindTheTickedPosition() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)
        await clock.waitForSleep()
        wall.advance(1)
        clock.advance()
        #expect(await iterator.next()?.position == 11)

        // The observed hardware bug: pausing re-emits the last registered
        // anchor, slightly behind what the ticker already showed — the shown
        // position must hold, never step back.
        feed.yield(line(position: 10.25, playing: false))
        let paused = await iterator.next()
        #expect(paused?.isPlaying == false)
        #expect(paused?.position == 11)
    }

    @Test func theFirstPauseFreezesInsteadOfDroppingToZero() async {
        // Symptom 1: the pause payload reports position 0; the scrubber must
        // hold the last shown value, not snap to the start.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)
        await clock.waitForSleep()
        wall.advance(1)
        clock.advance()
        #expect(await iterator.next()?.position == 11)

        feed.yield(line(position: 0, playing: false))
        let paused = await iterator.next()
        #expect(paused?.isPlaying == false)
        #expect(paused?.position == 11)
    }

    @Test func resumingFlowsImmediatelyFromTheFrozenPosition() async {
        // Symptom 2: after a pause frozen at 11, resuming must show that
        // position at once and keep advancing — no dwell while the ticker
        // catches up.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let clock = TestSleepClock()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: clock, tickInterval: 1, now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))
        #expect(await iterator.next()?.position == 10)
        await clock.waitForSleep()
        wall.advance(1)
        clock.advance()
        #expect(await iterator.next()?.position == 11)
        feed.yield(line(position: 0, playing: false))
        #expect(await iterator.next()?.position == 11)

        feed.yield(line(position: 11, playing: true))
        #expect(await iterator.next()?.position == 11)   // resync, shown at once
        await clock.waitForSleep()
        wall.advance(1)
        clock.advance()
        #expect(await iterator.next()?.position == 12)    // and it advances
    }

    @Test func aStaleInFlightTickCannotAdvanceAFreshAnchor() async {
        // Cancellation only covers the ticker's sleep: a tick that already woke
        // when a new anchor lands would add a full interval on top of a
        // position just aged to delivery time — and the reconciliation would
        // hold that overshoot for the rest of the track. The generation guard
        // is the fix; the timing can't be forced through the stream, so the
        // stale tick is driven directly.
        let (lines, feed) = AsyncStream<String>.makeStream()
        let wall = TestWallClock()
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines, availability: { true }, clock: TestSleepClock(), now: wall.now
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 10, playing: true))   // generation 1
        #expect(await iterator.next()?.position == 10)
        feed.yield(line(position: 20, playing: true))   // generation 2
        #expect(await iterator.next()?.position == 20)

        wall.advance(1)             // a second of real time is available to be claimed
        source.tick(ifCurrent: 1)   // the stale wake-up: must be a no-op

        // A same-position anchor exposes any illegitimate advance: had the
        // stale tick landed (21), it would also have been emitted here — and
        // reconciliation would hold it against this anchor.
        feed.yield(line(position: 20, playing: true))   // generation 3
        #expect(await iterator.next()?.position == 20)

        wall.advance(1)             // a second under the FRESH anchor
        source.tick(ifCurrent: 3)   // the live generation still ticks
        #expect(await iterator.next()?.position == 21)
    }

    @Test func agesTheAnchorToDeliveryUsingTheInjectedNow() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        // Anchor registered at epoch second 1_000_000; delivered 10 s later.
        let delivery = Date(timeIntervalSince1970: 1_000_010)
        let source = MediaRemoteAdapterNowPlayingSource(
            lines: lines,
            availability: { true },
            clock: TestSleepClock(),
            now: { delivery }
        )
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(#"{"type":"data","diff":false,"payload":{"title":"Breathe","playing":true,"elapsedTimeMicros":10000000,"timestampEpochMicros":1000000000000}}"#)

        #expect(await iterator.next()?.position == 20)
    }

    @Test func finishesWhenLineStreamEnds() async {
        let (lines, feed) = AsyncStream<String>.makeStream()
        let source = MediaRemoteAdapterNowPlayingSource(lines: lines, availability: { true }, clock: TestSleepClock())
        var iterator = source.updates.makeAsyncIterator()

        feed.yield(line(position: 1, playing: true))
        _ = await iterator.next()
        feed.finish()

        var sawNil = false
        for _ in 0..<20 where await iterator.next() == nil { sawNil = true; break }
        #expect(sawNil)
    }

    @Test func availabilityFollowsTheInjectedProbe() async {
        let (lines, _) = AsyncStream<String>.makeStream()
        #expect(await MediaRemoteAdapterNowPlayingSource(lines: lines, availability: { true }, clock: TestSleepClock()).isAvailable())
        let (lines2, _) = AsyncStream<String>.makeStream()
        #expect(await !MediaRemoteAdapterNowPlayingSource(lines: lines2, availability: { false }, clock: TestSleepClock()).isAvailable())
    }
}

// swiftlint:enable line_length
