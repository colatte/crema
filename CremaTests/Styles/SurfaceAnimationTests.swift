import CoreGraphics
import Foundation
import Testing
@testable import Crema

/// Pins the couplings between the calibratable animation values and the fixed
/// window/click machinery — every value invites hardware retuning, and these
/// are the retunes that would silently break geometry the tests otherwise
/// never see.
struct SurfaceAnimationTests {

    @Test func overshootHeadroomContainsTheOpenSpringsPeak() {
        // A critically underdamped spring overshoots by exp(-ζπ/√(1-ζ²)) of the
        // travelled delta; the fixed window only has `overshootHeadroom` of
        // room past the expanded frame before the morph clips at its edge.
        let damping = SurfaceAnimation.openDamping
        let overshootFraction = exp(-damping * .pi / (1 - damping * damping).squareRoot())

        let deltas: [CGFloat] = [
            NotchMetrics.expandedDrop - NotchMetrics.compactDrop,
            CardMetrics.expanded.height - CardMetrics.compact.height,
            // Largest per-side width travels of the hugging surface (the
            // surface is center-anchored, so each side moves half the delta):
            // a track change morphing a floor-hugging compact to the ceiling,
            // and a short-title hover expand crossing floors.
            (CardMetrics.compactMaxWidth - CardMetrics.compactMinWidth) / 2,
            (CardMetrics.expandedMinWidth - CardMetrics.compactMinWidth) / 2,
        ]
        for delta in deltas {
            #expect(overshootFraction * delta <= SurfaceAnimation.overshootHeadroom)
        }
    }

    @Test func interactiveSettleOutlastsTheCloseSpringsVisibleSettle() {
        // Tightening the click region before the close spring settles forwards
        // clicks through still-visible pixels to the window below.
        #expect(SurfaceAnimation.interactiveSettle >= 1.5 * SurfaceAnimation.closeResponse)
    }
}
