import CoreGraphics
import Testing
@testable import Crema

/// A window frame AppKit takes as asked: its origin on whole points, its centre
/// and pinned edge where the rule put them, never smaller than the rule's frame.
/// Every style's fixed window goes through it, on any screen geometry.
struct WindowPlacementTests {

    private let halfPoint = CGRect(x: 651.5, y: 817.5, width: 209, height: 164.5)

    @Test func theOriginLandsOnWholePointsAndTheCentreStays() {
        for anchor in [SurfaceVerticalAnchor.top, .bottom] {
            let placed = halfPoint.placeableAsWindow(anchor: anchor)
            #expect(placed.minX == placed.minX.rounded(), "\(anchor)")
            #expect(placed.midX == halfPoint.midX, "\(anchor)")
            #expect(placed.contains(halfPoint), "\(anchor)")
        }
    }

    @Test func thePinnedEdgeNeverMovesAndTheFreeOneReachesAWholePoint() {
        // A window hanging from its top grows down to a whole-point origin. One
        // standing on its bottom keeps that edge as asked, so the style must give
        // it a whole point: Classic's stands a whole number of points up the
        // screen (everyStylesWindowIsPlaceableOnAHalfPointSlit).
        let hanging = halfPoint.placeableAsWindow(anchor: .top)
        #expect(hanging.maxY == halfPoint.maxY)
        #expect(hanging.minY == hanging.minY.rounded())
        let bottomPinned = CGRect(x: 655.5, y: 140, width: 201, height: 211.5)
        let placed = bottomPinned.placeableAsWindow(anchor: .bottom)
        #expect(placed.minY == bottomPinned.minY)
        #expect(placed.maxY == placed.maxY.rounded(.up))
    }

    @Test func aWholePointFrameIsLeftAsItIs() {
        let whole = CGRect(x: 604, y: 40, width: 304, height: 140)
        #expect(whole.placeableAsWindow(anchor: .top) == whole)
        #expect(whole.placeableAsWindow(anchor: .bottom) == whole)
    }

    @Test func everyStylesWindowIsPlaceableOnAHalfPointSlit() {
        // The geometry the Notch was measured on: 663.5 pt each side of the slit.
        let notched = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32,
            auxLeft: 663.5,
            auxRight: 663.5
        )
        for style in Style.allCases {
            let window = style.windowFrame(on: notched)
            #expect(window.minX == window.minX.rounded(), "\(style)")
            #expect(window.minY == window.minY.rounded(), "\(style)")
        }
    }
}
