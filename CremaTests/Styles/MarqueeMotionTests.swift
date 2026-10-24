import CoreGraphics
import Testing
@testable import Crema

/// The marquee's run: a rest at the start, a steady slide that ends exactly where
/// it began, edges that fade only where text runs past them, and no motion at all
/// where the line fits or a veto stands (docs/DECISIONS.md:
/// a-long-title-scrolls-where-it-is-read).
struct MarqueeMotionTests {

    private let travel: CGFloat = 240

    @Test func itRestsAtItsStartBeforeEachRun() {
        #expect(MarqueeMotion.offset(elapsed: 0, travel: travel, cycleTravel: travel) == 0)
        #expect(MarqueeMotion.offset(elapsed: MarqueeMotion.rest - 0.01, travel: travel, cycleTravel: travel) == 0)
        let cycle = MarqueeMotion.rest + Double(travel / MarqueeMotion.speed)
        #expect(MarqueeMotion.offset(elapsed: cycle + MarqueeMotion.rest / 2, travel: travel, cycleTravel: travel) == 0)
    }

    @Test func itSlidesAtReadingPace() {
        let oneSecondIn = MarqueeMotion.offset(elapsed: MarqueeMotion.rest + 1, travel: travel, cycleTravel: travel)
        #expect(abs(oneSecondIn - MarqueeMotion.speed) < 0.001)
    }

    @Test func eachRunEndsOnTheFrameItStartedFrom() {
        // At `travel` the trailing copy sits where the first began, so the jump
        // back to zero for the next rest draws the same frame.
        let cycle = MarqueeMotion.rest + Double(travel / MarqueeMotion.speed)
        #expect(abs(MarqueeMotion.offset(elapsed: cycle - 0.0001, travel: travel, cycleTravel: travel) - travel) < 0.01)
        #expect(MarqueeMotion.offset(elapsed: cycle, travel: travel, cycleTravel: travel) == 0)
    }

    @Test func aDegenerateRunOrAClockBehindTheStartStaysAtRest() {
        #expect(MarqueeMotion.offset(elapsed: 5, travel: 0, cycleTravel: 0) == 0)
        #expect(MarqueeMotion.offset(elapsed: -3, travel: travel, cycleTravel: travel) == 0)
    }

    @Test func aShorterLineFinishesEarlyAndWaitsSoBothRestTogether() {
        // Title and artist share a run as long as the longer one needs; the
        // shorter one holds at its travel, which draws its starting frame.
        let short: CGFloat = 90
        let cycle = MarqueeMotion.rest + Double(travel / MarqueeMotion.speed)
        let shortDone = MarqueeMotion.rest + Double(short / MarqueeMotion.speed)
        #expect(MarqueeMotion.offset(elapsed: shortDone + 1, travel: short, cycleTravel: travel) == short)
        #expect(MarqueeMotion.offset(elapsed: cycle - 0.01, travel: short, cycleTravel: travel) == short)
        #expect(MarqueeMotion.offset(elapsed: cycle + 0.5, travel: short, cycleTravel: travel) == 0)
        #expect(MarqueeMotion.offset(elapsed: cycle + 0.5, travel: travel, cycleTravel: travel) == 0)
    }

    @Test func theLeadingEdgeFadesOnlyWhileTextRunsPastIt() {
        #expect(MarqueeMotion.edgeFades(offset: 0, travel: travel) == (0, MarqueeMotion.fade))
        #expect(MarqueeMotion.edgeFades(offset: 4, travel: travel).leading == 4)
        #expect(MarqueeMotion.edgeFades(offset: travel / 2, travel: travel).leading == MarqueeMotion.fade)
        #expect(MarqueeMotion.edgeFades(offset: travel, travel: travel).leading == 0)
    }

    @Test func theMaskIsOpaqueBetweenItsFadesAndNeverInvertsOnANarrowLine() {
        let stops = MarqueeMotion.maskStops(fades: (6, 12), lineWidth: 120)
        #expect(stops.map(\.location) == [0, 0.05, 0.9, 1])
        let narrow = MarqueeMotion.maskStops(fades: (12, 12), lineWidth: 10).map(\.location)
        #expect(narrow == narrow.sorted())
    }

    @Test func onlyALineAllowedToScrollAndTooLongForItsWidthMoves() {
        func moves(
            scrolls: Bool = true,
            full: CGFloat = 300,
            line: CGFloat = 200,
            reduceMotion: Bool = false,
            lowPower: Bool = false
        ) -> Bool {
            MarqueeMotion.moves(scrolls: scrolls, fullWidth: full, lineWidth: line,
                                reduceMotion: reduceMotion, lowPower: lowPower)
        }
        #expect(moves())
        #expect(!moves(scrolls: false))
        #expect(!moves(full: 200, line: 200))
        #expect(!moves(full: 200.4, line: 200))
        #expect(!moves(reduceMotion: true))
        #expect(!moves(lowPower: true))
    }
}
