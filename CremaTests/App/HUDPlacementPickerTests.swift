import CoreGraphics
import Testing
@testable import Crema

/// The placement tiles: eight small screens laid out where their places are, each
/// bar put on its tile by the Card's own placement rule. The grid is the one thing
/// written by hand, so it is checked against the rule: a tile in the wrong cell
/// would show one place and sit in another.
struct HUDPlacementPickerTests {

    private let size = PlacementThumbnail.size
    private let clearance = Thumbnail.floatingClearance

    @Test func theGridHoldsEveryPlacementOnceWithTheCentreEmpty() {
        let cells = PlacementThumbnail.grid.flatMap(\.self)
        #expect(PlacementThumbnail.grid.count == 3)
        #expect(PlacementThumbnail.grid.allSatisfy { $0.count == 3 })
        #expect(cells.compactMap(\.self).sorted { $0.rawValue < $1.rawValue }
            == HUDPlacement.allCases.sorted { $0.rawValue < $1.rawValue })
        #expect(PlacementThumbnail.grid[1][1] == nil)
    }

    @Test func eachTileSitsInTheCellOfItsOwnBar() {
        // The bar's centre, in thirds of the tile, names the cell it belongs in.
        for (row, cells) in PlacementThumbnail.grid.enumerated() {
            for (column, placement) in cells.enumerated() {
                guard let placement else { continue }
                let bar = PlacementThumbnail.barRect(for: placement)
                #expect(Int(bar.midX / (size.width / 3)) == column, "\(placement)")
                #expect(Int(bar.midY / (size.height / 3)) == row, "\(placement)")
            }
        }
    }

    @Test func everyBarStaysOnItsTileClearOfTheFrameAndTheMenuBar() {
        for placement in HUDPlacement.allCases {
            let bar = PlacementThumbnail.barRect(for: placement)
            #expect(bar.minX >= clearance, "\(placement)")
            #expect(bar.maxX <= size.width - clearance, "\(placement)")
            #expect(bar.minY >= PlacementThumbnail.menuBarHeight + clearance, "\(placement)")
            #expect(bar.maxY <= size.height - clearance, "\(placement)")
        }
    }

    @Test func barsOnOneEdgeLineUpAndCentredOnesStayCentred() {
        let bar = PlacementThumbnail.barRect(for:)
        // A corner stays a corner once the bar is magnified.
        #expect(bar(.topLeft).minX == bar(.middleLeft).minX)
        #expect(bar(.topLeft).minX == bar(.bottomLeft).minX)
        #expect(bar(.topRight).maxX == bar(.middleRight).maxX)
        #expect(bar(.topRight).maxX == bar(.bottomRight).maxX)
        #expect(bar(.topLeft).minY == bar(.topCenter).minY)
        #expect(bar(.topLeft).minY == bar(.topRight).minY)
        #expect(bar(.bottomLeft).maxY == bar(.bottomCenter).maxY)
        #expect(bar(.bottomLeft).maxY == bar(.bottomRight).maxY)
        #expect(abs(bar(.topCenter).midX - size.width / 2) < 0.001)
        #expect(abs(bar(.bottomCenter).midX - size.width / 2) < 0.001)
        #expect(abs(bar(.middleLeft).midY - bar(.middleRight).midY) < 0.001)
    }

    @Test func theBarStandsUprightOnTheTilesWhereItDoesOnScreen() {
        for placement in HUDPlacement.allCases {
            let bar = PlacementThumbnail.barRect(for: placement)
            #expect((bar.height > bar.width) == (placement.axis == .vertical), "\(placement)")
        }
        // One strip, magnified alike: upright is the flat bar transposed.
        let flat = PlacementThumbnail.barRect(for: .bottomCenter).size
        let upright = PlacementThumbnail.barRect(for: .middleLeft).size
        #expect(abs(flat.width / flat.height - upright.height / upright.width) < 0.001)
    }

    @Test func everyPlacementHasItsOwnName() {
        let names = HUDPlacement.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }
}
