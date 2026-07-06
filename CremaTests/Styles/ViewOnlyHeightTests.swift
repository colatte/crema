import CoreGraphics
import Testing
@testable import Crema

/// View-only (controls hidden) shrinks the expanded surface by exactly the
/// controls section, so the height stays "the sum of the visible sections" —
/// no pooled dead space. Pure arithmetic over the metrics; the same invariant
/// the normal expanded height already satisfies, now without the controls row.
struct ViewOnlyHeightTests {

    @Test func cardViewOnlyHeightIsTheVisibleSectionsExactly() {
        let visible = CardMetrics.contentPaddingVertical * 2
            + CardMetrics.expandedArtworkSide
            + CardMetrics.contentGap
            + CardMetrics.scrubberRowHeight
        #expect(CardMetrics.expanded.height - CardMetrics.controlsSectionHeight == visible)
    }

    @Test func classicViewOnlyHeightIsTheVisibleSectionsExactly() {
        let visible = ClassicMetrics.contentPadding * 2
            + ClassicMetrics.expandedArtworkSide
            + ClassicMetrics.contentGap
            + ClassicMetrics.textStackHeight
            + ClassicMetrics.contentGap
            + ClassicMetrics.scrubberRowHeight
        #expect(ClassicMetrics.expanded.height - ClassicMetrics.controlsSectionHeight == visible)
    }

    @Test func notchViewOnlyDropIsTheVisibleSectionsExactly() {
        let visible = NotchMetrics.expandedPaddingVertical * 2
            + NotchMetrics.expandedArtworkSide
            + NotchMetrics.expandedSectionGap
            + NotchMetrics.scrubberRowHeight
        #expect(NotchMetrics.expandedDrop - NotchMetrics.controlsSectionHeight == visible)
    }

    @Test func surfaceAnchorMatchesHowEachStyleDraws() {
        // The panel pins the reported interactive region to this edge; classic
        // grows up from its bottom line, the top-edge skins hang from the top.
        #expect(Style.notch.surfaceVerticalAnchor == .top)
        #expect(Style.card.surfaceVerticalAnchor == .top)
        #expect(Style.classic.surfaceVerticalAnchor == .bottom)
    }

    @Test func theControlsSectionIsTheRowPlusOneGap() {
        // The removed section is exactly the transport row and the single gap
        // above it — not the row alone (which would leave a dangling gap).
        #expect(CardMetrics.controlsSectionHeight == CardMetrics.contentGap + CardMetrics.controlsHeight)
        #expect(ClassicMetrics.controlsSectionHeight == ClassicMetrics.contentGap + ClassicMetrics.controlsHeight)
        #expect(NotchMetrics.controlsSectionHeight == NotchMetrics.expandedSectionGap + NotchMetrics.controlsHeight)
    }
}
