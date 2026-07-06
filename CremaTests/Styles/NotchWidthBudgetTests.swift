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

    @Test func transportFitsTheExpandedBandAtTheNarrowestScaleMode() {
        let slit = narrowest.frame.width - narrowest.auxLeft - narrowest.auxRight
        let content = slit - 2 * NotchMetrics.lateralInset - 2 * NotchMetrics.expandedPaddingHorizontal
        let transport = 3 * NotchMetrics.controlsHeight + 2 * NotchMetrics.controlsSpacing
        #expect(transport <= content)
    }
}
