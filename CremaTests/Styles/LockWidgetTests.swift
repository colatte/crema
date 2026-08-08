import CoreGraphics
import Testing
@testable import Crema

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

    @Test func aCentredPlacementWouldReachTheLoginOnAShorterPanel() {
        // The record of why the expanded state went, kept as arithmetic because
        // the arithmetic is the whole finding. The tile was 300 pt centred, so
        // its bottom edge was `(H - 300) / 2` — a function of a display height
        // the surface never read. On the author's 982 pt panel that is 341 and
        // everything clears; the measurement was then written down as if it
        // described the design rather than one panel.
        //
        // Two thresholds, both reachable. A 13-inch Air at its most-zoomed
        // scaled setting is 1024x640.
        func centredBottom(_ height: CGFloat) -> CGFloat { (height - 300) / 2 }

        // Three thresholds against three DIFFERENT numbers, and keeping them
        // apart is the point: `clearBandFloor` (300) is the app's own promise,
        // `Measured.clearFloor` (220) is what the ruler actually proved clear,
        // and `loginTop` (180) is where the login begins. Collapsing them is how
        // the original comment ended up describing a panel instead of a design.
        #expect(centredBottom(Measured.screenHeight) >= LockWidgetMetrics.clearBandFloor,
                "the panel it was designed on is exactly the one where it looked fine")
        #expect(centredBottom(880) < LockWidgetMetrics.clearBandFloor,
                "below 900 pt a centred tile crosses the floor the app promises")
        #expect(centredBottom(700) < Measured.clearFloor,
                "below 740 pt it leaves the band the ruler actually proved")
        #expect(centredBottom(640) < Measured.loginTop,
                "and below 660 pt it lands on the login itself")

        // What ships instead is not a function of the height at all.
        #expect(LockWidgetMetrics.bottomInset == LockWidgetMetrics.clearBandFloor)
    }

    @Test func theInsetClearsTheCardsOwnCorner() {
        #expect(LockWidgetMetrics.bottomInset > LockWidgetMetrics.cornerRadius)
    }
}

/// The decode bound, after the lock screen stopped needing one of its own.
struct ArtworkDecodeBoundTests {

    @Test func theSharedBoundCoversEveryArtworkTheAppDraws() {
        // The largest slot in the app is Classic's 88 pt cover; the lock card's
        // thumbnail is 50. At 2x those are 176 px and 100 px, and the shared
        // bound has to clear the larger.
        #expect(ArtworkDecoding.displayMaxSide >= 176)
        #expect(Double(ArtworkDecoding.displayMaxSide) >= LockWidgetMetrics.thumbnailSide * 2)
    }

    @Test func theLockScreenNoLongerNeedsABoundOfItsOwn() {
        // `lockScreenMaxSide` was 1024, sized for a 300 pt tile at 2x plus the
        // headroom a 1200 px archive cover wanted. Both are gone, and a bound
        // four times the largest slot is not caution, it is decode cost nobody
        // reads. Written as the relationship rather than the number so it fails
        // if a second bound is reintroduced without a slot to justify it.
        #expect(Double(ArtworkDecoding.displayMaxSide) < LockWidgetMetrics.thumbnailSide * 6)
    }
}

/// The card's own numbers, after the round that made it the whole surface.
struct LockCardDesignTests {

    @Test func theCoverRadiusIsConcentricWithTheCard() {
        // Apple's rule, and its worked example is this exact composition: the
        // inner radius of a nested container is the outer minus the padding.
        // Written as the arithmetic rather than the answer, so moving either
        // parent number cannot leave the child behind — which is how it drifted
        // to 9 against a 6 in the first place.
        #expect(
            LockWidgetMetrics.thumbnailRadius
                == LockWidgetMetrics.cornerRadius - LockWidgetMetrics.padding
        )
        // And the pair has to stay physically possible: a negative or zero inner
        // radius would mean the padding had swallowed the corner.
        #expect(LockWidgetMetrics.thumbnailRadius > 0)
        #expect(LockWidgetMetrics.thumbnailRadius < LockWidgetMetrics.cornerRadius)
    }

    @Test func theCardStillFitsInsideTheMeasuredBand() {
        // The sum-of-parts discipline, re-asserted after the rows changed: the
        // digits left the scrubber and the head kept its height, so the card's
        // height must not have moved.
        let top = LockWidgetMetrics.bottomInset + LockWidgetMetrics.collapsedHeight
        #expect(top <= 641, "the ceiling the ruler proved on the author's panel")
        #expect(LockWidgetMetrics.collapsedHeight == 152)
    }
}
