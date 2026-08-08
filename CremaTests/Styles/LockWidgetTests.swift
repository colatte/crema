import CoreGraphics
import Testing
@testable import Crema

/// The drift's whole decision, as a table written independently of the rule it
/// checks — the enum's own `&&` chain would agree with any mutation of itself.
///
/// Three vetoes, and the third is this surface's alone. Reduce Motion is the
/// standing accessibility preference; Low Power Mode is the system asking that
/// nothing be spent on movement; `settled` is time, which no other surface in
/// the app has to answer to because no other surface can be lit for eight hours
/// on a desk nobody is sitting at.
struct ArtworkDriftTests {

    @Test func noVetoIsTheOnlyWayItMoves() {
        #expect(ArtworkDrift.drifts(reduceMotion: false, lowPower: false, settled: false))
    }

    @Test func reduceMotionVetoesTheDrift() {
        // The accessibility preference outranks everything, and live: a user who
        // switches it on with the lock screen already up must see it stop.
        #expect(!ArtworkDrift.drifts(reduceMotion: true, lowPower: false, settled: false))
    }

    @Test func lowPowerModeVetoesTheDrift() {
        // Deleting `&& !lowPower` leaves every other assertion here green, which
        // is exactly why this one is written out.
        #expect(!ArtworkDrift.drifts(reduceMotion: false, lowPower: true, settled: false))
    }

    @Test func timeVetoesTheDrift() {
        // The veto this surface invents. Without it a repeatForever transform
        // runs all night on an idle machine — battery, and a burned-in rectangle
        // on the panels that burn in.
        #expect(!ArtworkDrift.drifts(reduceMotion: false, lowPower: false, settled: true))
    }

    /// One row written out rather than computed — a row that recomputed the rule
    /// would agree with any mutation of it.
    private struct Row {
        let reduceMotion: Bool
        let lowPower: Bool
        let settled: Bool
        let drifts: Bool
    }

    @Test func theWholeTruthTable() {
        let rows = [
            Row(reduceMotion: false, lowPower: false, settled: false, drifts: true),
            Row(reduceMotion: true, lowPower: false, settled: false, drifts: false),
            Row(reduceMotion: false, lowPower: true, settled: false, drifts: false),
            Row(reduceMotion: false, lowPower: false, settled: true, drifts: false),
            Row(reduceMotion: true, lowPower: true, settled: false, drifts: false),
            Row(reduceMotion: true, lowPower: false, settled: true, drifts: false),
            Row(reduceMotion: false, lowPower: true, settled: true, drifts: false),
            Row(reduceMotion: true, lowPower: true, settled: true, drifts: false),
        ]
        #expect(rows.count == 8)   // every combination of three booleans, none skipped
        for row in rows {
            #expect(
                ArtworkDrift.drifts(
                    reduceMotion: row.reduceMotion,
                    lowPower: row.lowPower,
                    settled: row.settled
                ) == row.drifts,
                "reduceMotion=\(row.reduceMotion) lowPower=\(row.lowPower) settled=\(row.settled)"
            )
        }
    }

    @Test func theSettleIsMinutesRatherThanSecondsOrHours() {
        // A bound rather than an exact value: the number is a judgement, but the
        // ORDER is a contract. Seconds would make the drift a blink; an hour
        // would make the veto decorative.
        #expect(ArtworkDrift.settlesAfter >= .seconds(60))
        #expect(ArtworkDrift.settlesAfter <= .seconds(600))
    }

    @Test func theTravelIsSmallEnoughToStayInsideTheOverscan() {
        // The drift must never expose an edge: the largest scale plus the travel
        // has to stay within what the overscan already covers.
        let reach = ArtworkDrift.travelledScale + ArtworkDrift.travel
        #expect(reach <= LockWidgetMetrics.backdropOverscan)
    }
}

/// The card's height is a sum of its parts, not a number someone measured off a
/// screenshot. These assertions exist so that removing a row from the layout
/// without removing its metric — or the reverse — fails here instead of leaving
/// a band of dead space nobody can explain.
struct LockWidgetMetricsTests {

    @Test func collapsedHeightIsTheSumOfWhatItDraws() {
        let expected = LockWidgetMetrics.padding
            + LockWidgetMetrics.headHeight
            + LockWidgetMetrics.gap
            + LockWidgetMetrics.scrubberHeight
            + LockWidgetMetrics.gap
            + LockWidgetMetrics.transportSide
            + LockWidgetMetrics.padding
        #expect(LockWidgetMetrics.collapsedHeight == expected)
        #expect(LockWidgetMetrics.collapsedSize.height == expected)
        #expect(LockWidgetMetrics.collapsedSize.width == LockWidgetMetrics.cardWidth)
    }

    @Test func theRowsFitInsideTheExpandedSquareWithCoverLeftOver() {
        // Expanded, the rows are laid OVER a 300 pt square rather than stacked
        // under a cover. If they ever grow past the tile they stop being a scrim
        // on artwork and become the artwork's replacement — and the fix would be
        // to shrink the rows, never to grow the tile, which is pinned to the
        // measured band.
        #expect(LockWidgetMetrics.expandedControlsHeight < LockWidgetMetrics.expandedSide)
        // At least half the square stays picture, or the point of expanding is
        // gone.
        #expect(LockWidgetMetrics.expandedControlsHeight < LockWidgetMetrics.expandedSide / 2)
    }

    @Test func theHeadIsTallEnoughForBothThingsItCanHold() {
        #expect(LockWidgetMetrics.headHeight >= LockWidgetMetrics.thumbnailSide)
        #expect(LockWidgetMetrics.headHeight >= LockWidgetMetrics.textBlockHeight)
    }

    // MARK: - Placement, against what the ruler measured

    /// The lock screen, as measured on hardware with
    /// `scripts/probes/lockscreen-geometry.swift`, on the author's 1512×982 pt
    /// panel. Two runs: 2026-08-07 established that a card at 96 pt lands on the
    /// avatar and that a centred 300 pt square touches nothing; 2026-08-08
    /// answered the question the first run asked and never recorded — where the
    /// login's top edge is — and read candidate B clear as well.
    ///
    /// This table replaces one that was fiction in both operands: it put the
    /// login's top at "about 250 pt" on an attributed 1440×900 display. Neither
    /// number came off the ruler, and 1 − 250/900 = 72.2% is where a "72% of the
    /// height" reached CLAUDE.md and nearly reached the code. The unit is points
    /// off the bottom edge, and no fraction of the display height appears here or
    /// in the surface.
    ///
    /// These are the numbers the placement has to satisfy. They are written here
    /// independently of the production constants — a table restating
    /// `bottomInset` would agree with any value it was given.
    private enum Measured {
        static let screenHeight: CGFloat = 982

        /// The login block's top edge — the avatar's top; the name and the
        /// password field sit below it. Read AT the teal scale's floor, so the
        /// honest reading is "at or below 180": a true edge at 160 would produce
        /// the same answer. Only the upper bound is load-bearing, and it holds
        /// either way.
        static let loginTop: CGFloat = 180

        /// Candidate B, read completely clear on the second run. The first run
        /// proved only the centred square, which is the whole reason
        /// `clearBandFloor = 300` briefly looked 41 pt short of anything.
        static let clearFloor: CGFloat = 220

        /// The centred 300 pt square's top on this panel. B (220…372) and the
        /// square (341…641) overlap, so what the two runs prove together is one
        /// clear interval rather than two islands.
        static let clearCeiling: CGFloat = 641
    }

    @Test func theCollapsedCardSitsAboveTheLoginRatherThanOnIt() {
        // The bug this replaces: 96 pt, taken from a mock, put the card exactly
        // on the avatar and the password field. Sonoma moved the login DOWN, so
        // the old comment claiming the inset cleared them was not merely
        // unproven — it described the opposite of what the screen does.
        let bottom = LockWidgetMetrics.bottomInset
        #expect(bottom >= Measured.loginTop)
        #expect(bottom >= Measured.clearFloor)
        // And the whole card, not just its bottom edge, has to stay under the
        // clear band's ceiling.
        #expect(bottom + LockWidgetMetrics.collapsedHeight <= Measured.clearCeiling)
    }

    @Test func theExpandedSquareIsExactlyTheRectangleThatWasMeasuredClear() {
        // Centring the tile on the display is what makes the measurement
        // transferable: the ruler proved a 300 pt square at the centre, so the
        // tile must be that square and no larger. The version this replaced was
        // a stack of cover + card — 464 pt, and it leaves the band at the TOP
        // (723 > 641), not at the bottom: measured, it clears the login by 79 pt.
        // The test twenty lines below pins that correction; this comment used to
        // contradict it.
        let side = LockWidgetMetrics.expandedSide
        let bottom = (Measured.screenHeight - side) / 2
        #expect(bottom >= Measured.clearFloor)
        #expect(bottom + side <= Measured.clearCeiling)
        #expect(side <= Measured.clearCeiling - Measured.clearFloor)
    }

    @Test func aStackedCompositionWouldLeaveTheBandThatWasMeasured() {
        // Kept as the record of why the design changed — with the reason
        // corrected, because the original one was measured FALSE on 2026-08-08.
        // It read "centring it puts its bottom edge inside the login's strip",
        // arithmetic done against a 900 pt display and a login top of 250 that
        // neither existed. On the real 982 pt panel the stack centres to
        // 259…723: its bottom clears the login by 79 pt.
        //
        // What is true is the other end. 723 is outside 641, the ceiling the
        // ruler actually proved, so the stack would have put a large picture
        // where nobody has looked. That plus the interaction reason — a hero
        // above a card is a big image that ignores every click aimed at it,
        // since only the drawn surface takes one here — is what the decision
        // rests on now.
        let stacked = LockWidgetMetrics.expandedSide
            + LockWidgetMetrics.gap
            + LockWidgetMetrics.collapsedHeight
        let bottom = (Measured.screenHeight - stacked) / 2
        #expect(bottom + stacked > Measured.clearCeiling, "the stack leaves the measured band")
        // And the claim that replaced it is pinned as false, so nobody restores
        // the old sentence from memory.
        #expect(bottom > Measured.loginTop, "the stack did NOT reach the login — that reason was wrong")
    }

    @Test func theInsetClearsTheCardsOwnCorner() {
        #expect(LockWidgetMetrics.bottomInset > LockWidgetMetrics.cornerRadius)
    }
}

/// The lock screen's decode bound is its own, and the reason is a cost the rest
/// of the app must not pay.
struct LockScreenArtworkBoundTests {

    @Test func theLockScreenDecodesLargerThanEveryDesktopSlot() {
        // A 300 pt cover at 2× is 600 px; the shared bound is 256, sized for an
        // 88 pt thumbnail. Raising the shared one instead would make every
        // thumbnail in every skin pay for a size only this surface shows.
        #expect(ArtworkDecoding.lockScreenMaxSide > ArtworkDecoding.displayMaxSide)
        #expect(Double(ArtworkDecoding.lockScreenMaxSide) >= LockWidgetMetrics.expandedSide * 2)
    }

    @Test func theSharedBoundStillFitsTheLargestDesktopSlot() {
        // 88 pt is the biggest artwork any desktop skin draws (Classic,
        // expanded); at 2× that is 176 px and the bound must stay above it.
        #expect(ArtworkDecoding.displayMaxSide >= 176)
    }
}
