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

    /// The lock screen, as measured on hardware 2026-08-07 with
    /// `scripts/probes/lockscreen-geometry.swift` on a 1440×900 pt display: the
    /// login (avatar, name, password field) owns the bottom strip up to about
    /// 250 pt, and a 300 pt square centred on the display touched nothing.
    ///
    /// These are the numbers the placement has to satisfy. They are written here
    /// independently of the production constants — a table restating
    /// `bottomInset` would agree with any value it was given.
    private enum Measured {
        static let screenHeight: CGFloat = 900
        static let loginTop: CGFloat = 250
        static let clearFloor: CGFloat = 300
        static let clearCeiling: CGFloat = 600
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
        // tile must be that square and no larger. A stack of cover + card would
        // be ~470 pt and its bottom edge would land back on the login, which is
        // the version this replaced.
        let side = LockWidgetMetrics.expandedSide
        let bottom = (Measured.screenHeight - side) / 2
        #expect(bottom >= Measured.clearFloor)
        #expect(bottom + side <= Measured.clearCeiling)
        #expect(side <= Measured.clearCeiling - Measured.clearFloor)
    }

    @Test func aStackedCompositionWouldNotHaveFit() {
        // Kept as the record of why the design changed rather than the metric.
        // Cover + gap + card is the shape that was drawn first; centring it puts
        // its bottom edge inside the login's strip.
        let stacked = LockWidgetMetrics.expandedSide
            + LockWidgetMetrics.gap
            + LockWidgetMetrics.collapsedHeight
        let bottom = (Measured.screenHeight - stacked) / 2
        #expect(bottom < Measured.loginTop, "the stack is what the tile exists to avoid")
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
