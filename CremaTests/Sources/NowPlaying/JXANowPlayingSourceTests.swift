import Foundation
import Testing
@testable import Crema

/// The JXA fallback source over an injectable query + clock (no osascript): the
/// poll loop yields only when the track changes, and when the player stops it
/// re-emits the last track as not-playing so the Coordinator hides it — the same
/// dedup/hide contract the adapter twin (MediaRemoteAdapterNowPlayingSource) carries.
@MainActor
struct JXANowPlayingSourceTests {

    /// Thread-safe holder for the JSON the fake query returns: the poll task
    /// reads it off the main thread while the test rewrites it between polls.
    private final class QueryBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _json: String?
        init(_ json: String?) { _json = json }
        var json: String? {
            get { lock.withLock { _json } }
            set { lock.withLock { _json = newValue } }
        }
    }

    private func track(_ title: String, playing: Bool) -> String {
        #"{"title":"\#(title)","artist":"Pink Floyd","duration":169.0,"position":42.0,"playing":\#(playing)}"#
    }

    @Test func emitsTheFirstPolledTrack() async {
        let box = QueryBox(track("Breathe", playing: true))
        let source = JXANowPlayingSource(query: { box.json }, clock: TestSleepClock())
        var iterator = source.updates.makeAsyncIterator()

        let first = await iterator.next()
        #expect(first?.title == "Breathe")
        #expect(first?.isPlaying == true)
    }

    @Test func anUnchangedTrackDoesNotEmitAgain() async {
        let box = QueryBox(track("Breathe", playing: true))
        let clock = TestSleepClock()
        let source = JXANowPlayingSource(query: { box.json }, clock: clock)
        var iterator = source.updates.makeAsyncIterator()

        #expect(await iterator.next()?.title == "Breathe")   // first poll

        // A second poll with the same track must be silent; the next value the
        // iterator surfaces is the changed track from the third poll, proving
        // the identical poll in between emitted nothing.
        await clock.waitForSleep()
        clock.advance()                                      // poll 2: same track
        await clock.waitForSleep()
        box.json = track("Time", playing: true)
        clock.advance()                                      // poll 3: changed

        #expect(await iterator.next()?.title == "Time")
    }

    @Test func stoppingRepublishesTheLastTrackAsNotPlaying() async {
        let box = QueryBox(track("Breathe", playing: true))
        let clock = TestSleepClock()
        let source = JXANowPlayingSource(query: { box.json }, clock: clock)
        var iterator = source.updates.makeAsyncIterator()

        #expect(await iterator.next()?.isPlaying == true)    // first poll

        await clock.waitForSleep()
        box.json = "{}"                                      // player stopped
        clock.advance()

        // The last track is re-emitted paused (not dropped) so the Coordinator
        // hides it — browser-only playback is invisible to JXA, so a bare "gone"
        // could never reach the off state.
        let hidden = await iterator.next()
        #expect(hidden?.isPlaying == false)
        #expect(hidden?.title == "Breathe")
    }
}
