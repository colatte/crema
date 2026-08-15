import CoreGraphics
import Testing
@testable import Crema

/// The expanded band's content must fit every scale mode of a notched display:
/// the physical cutout is constant, so the slit in points shrinks with the
/// logical resolution — a block sized against the default mode silently
/// overflows the padding on the narrower ones.
@MainActor
struct NotchWidthBudgetTests {

    /// The 14" MBP's narrowest scaled mode ("larger text", 1024×665): the
    /// default mode's 185 pt slit scales to 185 × 1024/1512 ≈ 125.3 pt.
    private let narrowest = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1024, height: 665),
        safeTop: 21.7,
        auxLeft: 449.35,
        auxRight: 449.35
    )

    private let track = CoordinatorHarness.playingTrack()

    @Test func transportFitsTheExpandedBandAtTheNarrowestScaleMode() {
        let slit = narrowest.frame.width - narrowest.auxLeft - narrowest.auxRight
        let content = slit - 2 * NotchMetrics.lateralInset - 2 * NotchMetrics.expandedPaddingHorizontal
        let transport = 3 * NotchMetrics.controlsHeight + 2 * NotchMetrics.controlsSpacing
        #expect(transport <= content)
    }

    /// The other budget on the same row, and the one nobody was watching: what is
    /// LEFT for the title once the cover and the gaps are paid.
    ///
    /// The arithmetic, at the narrowest mode: the 125.3 pt slit is snapped inward
    /// to device pixels by the frame rule (125.0 drawn), 24 goes to the horizontal
    /// padding, 36 to the cover and 8 to the header gap — 57 pt of title column.
    /// The floor is 55: two points of slack for a re-calibrated cover or gap, and
    /// no more. It is a floor rather than an equality because the number is a
    /// budget, not a design constant — but it is DECLARED, because the title is
    /// the reason the band opens at all, and an undeclared column is one nobody
    /// notices being spent: the cover, the gaps and a Spacer's doubled charge all
    /// came out of this number before anyone counted it. Read off the frame rule
    /// instead of the raw slit, so the pixel snap is inside the budget rather than
    /// eating into its slack.
    @Test func theTitleColumnKeepsItsFloorAtTheNarrowestScaleMode() {
        let surface = NotchStyle().frame(for: .nowPlaying(track, expanded: true), on: narrowest).width
        let content = surface - 2 * NotchMetrics.expandedPaddingHorizontal
        let titleColumn = content - NotchMetrics.expandedArtworkSide - NotchMetrics.expandedGap
        #expect(titleColumn >= 55, "the expanded title column is down to \(titleColumn) pt")
    }
}
