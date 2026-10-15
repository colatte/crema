import CoreGraphics
import Testing
@testable import Crema

/// The skins' radii as the shape rules they follow, never as literals: a fixed
/// radius at a third of the HUD's height, and a nested cover concentric with the
/// surface corner it sits in — the parent's radius minus the tighter inset
/// (docs/DECISIONS.md: inner-corners-are-concentric). A retuned size or padding
/// keeps these green only if the radius follows it.
struct CardMetricsShapeTests {

    @Test func theHUDRadiusIsAThirdOfItsHeight() {
        #expect(CardMetrics.hudSystemCornerRadius == CardMetrics.hudSystemHeight / 3)
        // A fixed shape, not a capsule: the radius stays short of half the height,
        // so straight runs remain on the short sides too.
        #expect(CardMetrics.hudSystemCornerRadius < CardMetrics.hudSystemHeight / 2)
    }

    @Test func theFilledGlyphStartsWhereTheCornerEnds() {
        // At an inset of at least the radius, the corner's arc has met the edge
        // before the glyph begins, in either orientation (the bar is equally thick
        // both ways).
        #expect(CardMetrics.hudFilledIconInset >= CardMetrics.hudSystemCornerRadius)
        #expect(CardMetrics.hudFilledIconInset < CardMetrics.hudSystemWidth / 2)
    }

    @Test func theCompactCoverIsConcentricWithTheCard() {
        // The cover is centred in the strip's height and padded from the side.
        let vertical = (CardMetrics.compact.height - CardMetrics.compactArtworkSide) / 2
        let horizontal = CardMetrics.contentPaddingHorizontal
        let tighter = min(vertical, horizontal)
        // Nested: the inset sits inside the card's corner curve.
        #expect(tighter < CardMetrics.cornerRadius)
        #expect(CardMetrics.compactArtworkRadius == CardMetrics.cornerRadius - tighter)
    }

    @Test func theExpandedCoverIsConcentricWithTheCard() {
        // The header hangs contentPaddingVertical below the top, padded from the side.
        let tighter = min(CardMetrics.contentPaddingVertical, CardMetrics.contentPaddingHorizontal)
        #expect(tighter < CardMetrics.cornerRadius)
        #expect(CardMetrics.expandedArtworkRadius == CardMetrics.cornerRadius - tighter)
    }

    @Test func theNotchCompactCoverIsConcentricWithTheBandsBase() {
        // Centred in the drop below the slit, padded from the side; the base
        // corners carry the bottom radius.
        let vertical = (NotchMetrics.compactDrop - NotchMetrics.compactArtworkSide) / 2
        let tighter = min(vertical, NotchMetrics.contentPaddingHorizontal)
        #expect(tighter < NotchMetrics.compactBottomRadius)
        #expect(NotchMetrics.compactArtworkRadius == NotchMetrics.compactBottomRadius - tighter)
    }

    @Test func theSliderRowFitsTheHUDAcrossAndAlong() {
        // Across the bar: the capsule's hit row and the knob both fit the HUD's
        // thickness, horizontal and upright alike (upright is the transpose).
        #expect(CapsuleTrack.trackHitHeight <= CardMetrics.hudSystemHeight)
        #expect(CapsuleTrack.knobSize.height <= CardMetrics.hudSystemHeight)
        #expect(CapsuleTrack.knobSize.width <= CardMetrics.hudSystemHeight)
        #expect(CardHUDIndicator.hudIconSlot <= CardMetrics.hudSystemHeight)
        // Along the bar: padding at both ends, the icon slot and the gap leave the
        // capsule a track longer than its knob, so it still travels.
        let track = CardMetrics.hudSystemWidth
            - 2 * CardMetrics.contentPaddingHorizontal
            - CardHUDIndicator.hudIconSlot
            - CardMetrics.contentGap
        #expect(track == 146)
        #expect(track > CapsuleTrack.knobSize.width)
    }
}
