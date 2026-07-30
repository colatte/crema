import Testing
@testable import Crema

/// The coalescing window in front of the one reading in this app with a
/// system-wide side effect: `CGGetEventTapList` resets the min/max latency
/// counters of EVERY tap in the system, neighbouring apps' included, and the
/// caller is a view body SwiftUI rebuilds whenever it likes — so a burst of
/// rebuilds must cost one reading, and the answer must never be stale for longer
/// than the window, because the stale answer here is an accusation against a named
/// neighbour (docs/DECISIONS.md: media-key-chain-contention,
/// menu-status-before-warnings).
///
/// Nothing here touches the real registry, and nothing waits on wall time: the
/// window is the subject, so the clock is driven by hand.
@MainActor
struct MediaKeyChainNoticeCacheTests {

    /// A clock the test moves itself. Not SleepClock: there is nothing parked here
    /// to advance, only a timestamp to read.
    private final class Hand {
        var instant = ContinuousClock.now
        func advance(by duration: Duration) { instant = instant.advanced(by: duration) }
    }

    @Test func aBurstOfRebuildsCostsOneReadingAndTheWindowStillExpires() {
        let hand = Hand()
        let cache = MediaKeyChainNotice.Cache(window: .seconds(1), now: { hand.instant })
        var reads = 0
        func read() -> MediaKeyChainNotice {
            cache.notice(betterDisplayIsFeedingUs: false) { _ in
                reads += 1
                return .anotherAppAhead("Some Other App")
            }
        }

        #expect(read() == .anotherAppAhead("Some Other App"))
        hand.advance(by: .milliseconds(300))
        #expect(read() == .anotherAppAhead("Some Other App"))
        hand.advance(by: .milliseconds(300))
        #expect(read() == .anotherAppAhead("Some Other App"))
        #expect(reads == 1)   // three menu rebuilds, one CGGetEventTapList

        // Past the window the next rebuild reads again — which is what keeps a
        // neighbour that installed or dropped a tap with no notification behind it
        // from being accused (or excused) for longer than the window.
        hand.advance(by: .seconds(1))
        #expect(read() == .anotherAppAhead("Some Other App"))
        #expect(reads == 2)
    }

    @Test func aFlipOfTheNeighboursReportRereadsInsideTheWindow() {
        // The neighbour's delivered payload is a free local flag that can flip with
        // no notification at all, so it is part of the memo KEY and not of its age:
        // there is no wiring that can forget it and no window to wait out.
        let hand = Hand()
        let cache = MediaKeyChainNotice.Cache(window: .seconds(1), now: { hand.instant })
        var reads = 0
        func read(feeding: Bool) -> MediaKeyChainNotice {
            cache.notice(betterDisplayIsFeedingUs: feeding) { isFeeding in
                reads += 1
                return isFeeding ? .drawingFromBetterDisplay : .betterDisplayAheadAndSilent
            }
        }

        #expect(read(feeding: false) == .betterDisplayAheadAndSilent)
        #expect(read(feeding: true) == .drawingFromBetterDisplay)   // no time passed
        #expect(reads == 2)
        #expect(read(feeding: true) == .drawingFromBetterDisplay)
        #expect(reads == 2)   // and the new answer is the memoized one
    }

    @Test func theShippedWindowBothCoalescesAndExpires() {
        // The default the app runs with, not a test-only value: long enough to
        // swallow a rebuild burst, short enough that a user who changed something
        // and came to look sees the truth.
        let hand = Hand()
        let cache = MediaKeyChainNotice.Cache(now: { hand.instant })
        var reads = 0
        func read() -> MediaKeyChainNotice {
            cache.notice(betterDisplayIsFeedingUs: false) { _ in
                reads += 1
                return .quiet
            }
        }

        _ = read()
        hand.advance(by: .milliseconds(50))
        _ = read()
        #expect(reads == 1)

        hand.advance(by: .seconds(30))
        _ = read()
        #expect(reads == 2)
    }
}
