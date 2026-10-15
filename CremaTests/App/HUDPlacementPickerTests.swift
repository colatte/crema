import CoreGraphics
import Testing
@testable import Crema

/// The placement map: one screen with the card resting at the top and every place
/// the HUD can go drawn on it by the Card's own rules. What a person aims at is a
/// target around each mark, so the targets must cover every place, never overlap,
/// and stay on the picture.
struct HUDPlacementPickerTests {

    private let size = PlacementMap.size
    private let picture = CGRect(origin: .zero, size: PlacementMap.size)
    private let room = PlacementMap.edgeRoom
    private let off = HUDPlacement.allCases.filter { $0 != .topCenter }

    @Test func everyPlaceHasATargetOnThePictureAndNoTwoOverlap() {
        let targets = HUDPlacement.allCases.map(PlacementMap.target(for:))
        for (placement, target) in zip(HUDPlacement.allCases, targets) {
            #expect(!target.isEmpty, "\(placement)")
            #expect(picture.contains(target), "\(placement)")
        }
        // Kills a slop or magnification grown until one click lands on two places.
        for i in targets.indices {
            for j in targets.indices where j > i {
                #expect(!targets[i].intersects(targets[j]), "\(HUDPlacement.allCases[i]) / \(HUDPlacement.allCases[j])")
            }
        }
    }

    @Test func eachTargetHoldsItsMarkWithRoomAround() {
        for placement in off {
            let bar = PlacementMap.barRect(for: placement)
            let target = PlacementMap.target(for: placement)
            #expect(target.contains(bar), "\(placement)")
            #expect(target.width > bar.width && target.height > bar.height, "\(placement)")
        }
        // The top centre is the card, and the bar that replaces it once chosen.
        let top = PlacementMap.target(for: .topCenter)
        #expect(top.contains(PlacementMap.cardRect))
        #expect(top.contains(PlacementMap.barRect(for: .topCenter)))
    }

    @Test func everyMarkKeepsRoomForItsRingFromTheFrameTheMenuBarAndTheCard() {
        // A chosen place on an edge is ringed whole: the ring sits outside the mark,
        // so the mark keeps the ring's room from the frame and the menu bar, and the
        // ring stays inside the place's own target.
        #expect(room >= PlacementMap.ringInset + PlacementMap.ringWidth)
        #expect(PlacementMap.hitSlop >= PlacementMap.ringInset + PlacementMap.ringWidth)
        for placement in HUDPlacement.allCases {
            let bar = PlacementMap.barRect(for: placement)
            #expect(bar.minX >= room, "\(placement)")
            #expect(bar.maxX <= size.width - room, "\(placement)")
            #expect(bar.minY >= PlacementMap.menuBarHeight + room, "\(placement)")
            #expect(bar.maxY <= size.height - room, "\(placement)")
        }
        for placement in off {
            #expect(!PlacementMap.barRect(for: placement).intersects(PlacementMap.cardRect), "\(placement)")
        }
    }

    @Test func theCardAndTheTopBarsHangFromOneLine() {
        // On screen the card and every top placement hang from the same anchor
        // below the menu bar; the picture keeps that.
        let line = PlacementMap.cardRect.minY
        #expect(PlacementMap.cardRect.minY >= PlacementMap.menuBarHeight + room)
        for placement in [HUDPlacement.topLeft, .topCenter, .topRight] {
            #expect(abs(PlacementMap.barRect(for: placement).minY - line) < 0.001, "\(placement)")
        }
        #expect(abs(PlacementMap.cardRect.midX - size.width / 2) < 0.001)
    }

    @Test func barsOnOneEdgeLineUpAndCentredOnesStayCentred() {
        let bar = PlacementMap.barRect(for:)
        // A corner stays a corner once the bar is magnified.
        #expect(bar(.topLeft).minX == bar(.middleLeft).minX)
        #expect(bar(.topLeft).minX == bar(.bottomLeft).minX)
        #expect(bar(.topRight).maxX == bar(.middleRight).maxX)
        #expect(bar(.topRight).maxX == bar(.bottomRight).maxX)
        #expect(bar(.bottomLeft).maxY == bar(.bottomCenter).maxY)
        #expect(bar(.bottomLeft).maxY == bar(.bottomRight).maxY)
        #expect(abs(bar(.topCenter).midX - size.width / 2) < 0.001)
        #expect(abs(bar(.bottomCenter).midX - size.width / 2) < 0.001)
        #expect(abs(bar(.middleLeft).midY - bar(.middleRight).midY) < 0.001)
    }

    @Test func theBarAndTheCardKeepTheirTrueProportion() {
        // One magnification for both: a bar exaggerated alone would picture a HUD
        // as large as the card it is smaller than.
        let bar = PlacementMap.barRect(for: .bottomCenter)
        let card = PlacementMap.cardRect
        let real = CardMetrics.hudSystemWidth / CardMetrics.compact.width
        #expect(abs(bar.width / card.width - real) < 0.001)
        for placement in HUDPlacement.allCases {
            let rect = PlacementMap.barRect(for: placement)
            #expect((rect.height > rect.width) == (placement.axis == .vertical), "\(placement)")
        }
        let flat = PlacementMap.barRect(for: .bottomCenter).size
        let upright = PlacementMap.barRect(for: .middleLeft).size
        #expect(abs(flat.width / flat.height - upright.height / upright.width) < 0.001)
    }

    @Test func everyPlacementHasItsOwnName() {
        let names = HUDPlacement.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }
}
