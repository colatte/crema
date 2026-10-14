import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// Where the Card draws its HUD: a pure rule of (placement, ScreenGeometry). The
/// top centre is the card's own spot, so it must stay the HUD frame every Card
/// already draws; the other seven sit on the screen's edges, upright only in the
/// middle of a side.
struct HUDPlacementTests {

    private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    /// A second display left of and above the main one: the rule reads the
    /// screen's own origin, never assumes zero.
    private let offset = ScreenGeometry(frame: CGRect(x: -1280, y: 400, width: 1280, height: 800))
    private var geometries: [ScreenGeometry] { [plain, notched, offset] }

    private enum Row { case top, middle, bottom }
    private enum Column { case left, center, right }

    private func row(_ placement: HUDPlacement) -> Row {
        switch placement {
        case .topLeft, .topCenter, .topRight: .top
        case .middleLeft, .middleRight: .middle
        case .bottomLeft, .bottomCenter, .bottomRight: .bottom
        }
    }

    private func column(_ placement: HUDPlacement) -> Column {
        switch placement {
        case .topLeft, .middleLeft, .bottomLeft: .left
        case .topCenter, .bottomCenter: .center
        case .topRight, .middleRight, .bottomRight: .right
        }
    }

    @Test @MainActor func theTopCenterIsTheHUDFrameEveryCardAlreadyDraws() {
        // Kills a second description of the card's HUD spot drifting from the
        // first: the default placement must morph from the now-playing card, so
        // it is the frame rule's own `.hud` frame, notch and origin included.
        let hud = PresentationState.hud(SystemHUD(kind: .volume, value: 0.5))
        for geometry in geometries {
            #expect(CardStyle.hudFrame(at: .topCenter, on: geometry) == CardStyle().frame(for: hud, on: geometry))
        }
        #expect(HUDPlacement.shippedDefault == .topCenter)
    }

    @Test func everyPlacementSitsOnItsEdges() {
        for geometry in geometries {
            let screen = geometry.frame
            for placement in HUDPlacement.allCases {
                let frame = CardStyle.hudFrame(at: placement, on: geometry)
                switch row(placement) {
                case .top:
                    #expect(frame.maxY == screen.maxY - geometry.safeTop - CardMetrics.topMargin, "\(placement)")
                case .middle:
                    #expect(frame.midY == screen.midY, "\(placement)")
                case .bottom:
                    #expect(frame.minY == screen.minY + CardMetrics.hudBottomMargin, "\(placement)")
                }
                switch column(placement) {
                case .left:
                    #expect(frame.minX == screen.minX + CardMetrics.hudSideMargin, "\(placement)")
                case .center:
                    #expect(frame.midX == screen.midX, "\(placement)")
                case .right:
                    #expect(frame.maxX == screen.maxX - CardMetrics.hudSideMargin, "\(placement)")
                }
            }
        }
    }

    @Test func theBarStandsUprightOnlyInTheMiddleOfASide() {
        // The bar runs along the edge it sits on: upright on the middle of a
        // side, flat along the top and bottom edges, corners included.
        for placement in HUDPlacement.allCases {
            let upright = placement == .middleLeft || placement == .middleRight
            #expect(placement.axis == (upright ? .vertical : .horizontal), "\(placement)")
            let size = CardStyle.hudFrame(at: placement, on: plain).size
            #expect(size == CardMetrics.hudSize(for: placement.axis), "\(placement)")
        }
        // Upright is the same strip transposed, never a second declared size.
        let flat = CardMetrics.hudSize(for: .horizontal)
        let upright = CardMetrics.hudSize(for: .vertical)
        #expect(flat == CardMetrics.hudSystemSize)
        #expect(upright.width == flat.height)
        #expect(upright.height == flat.width)
    }

    @Test func everyPlacementPersistsUnderItsOwnName() {
        // The rawValue is the stored preference: renaming a case would put every
        // user who chose it back on the default without a word.
        #expect(HUDPlacement.allCases.map(\.rawValue) == [
            "topLeft", "topCenter", "topRight",
            "middleLeft", "middleRight",
            "bottomLeft", "bottomCenter", "bottomRight",
        ])
    }

    @Test func everyPlacementStaysOnItsScreen() {
        for geometry in geometries {
            for placement in HUDPlacement.allCases {
                #expect(geometry.frame.contains(CardStyle.hudFrame(at: placement, on: geometry)), "\(placement)")
            }
        }
    }
}
