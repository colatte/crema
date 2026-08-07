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

    @Test func expandedHeightDropsExactlyTheCoverAndNothingElse() {
        // Expanding removes the thumbnail from the head row and nothing more, so
        // the card must shrink by exactly the difference between the cover and
        // the words it stood beside. Any other delta means a row went missing.
        let delta = LockWidgetMetrics.collapsedHeight - LockWidgetMetrics.expandedCardHeight
        #expect(delta == LockWidgetMetrics.headHeight - LockWidgetMetrics.textBlockHeight)
    }

    @Test func theHeadIsTallEnoughForBothThingsItCanHold() {
        #expect(LockWidgetMetrics.headHeight >= LockWidgetMetrics.thumbnailSide)
        #expect(LockWidgetMetrics.headHeight >= LockWidgetMetrics.textBlockHeight)
    }

    @Test func theCardClearsTheAvatarAndTheHeroClearsTheCard() {
        // The password field and the avatar own the middle and low centre of the
        // lock screen. The inset is what keeps the card off them, and it has to
        // be more than the card's own corner radius or the two visually collide.
        #expect(LockWidgetMetrics.bottomInset > LockWidgetMetrics.cornerRadius)
        // The cover is the subject once expanded: it must read as larger than
        // the card that used to hold it.
        #expect(LockWidgetMetrics.heroSide > LockWidgetMetrics.expandedCardWidth * 0.8)
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
        #expect(Double(ArtworkDecoding.lockScreenMaxSide) >= LockWidgetMetrics.heroSide * 2)
    }

    @Test func theSharedBoundStillFitsTheLargestDesktopSlot() {
        // 88 pt is the biggest artwork any desktop skin draws (Classic,
        // expanded); at 2× that is 176 px and the bound must stay above it.
        #expect(ArtworkDecoding.displayMaxSide >= 176)
    }
}
