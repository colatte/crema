import AppKit
import Testing
@testable import Crema

/// The Position pop-up: its rows cover the eight places once each, in the order
/// they sit on the glass, and each item's icon draws the bar where the Card's
/// rule puts it — on the right edge and third, upright in the middle of a side,
/// inside the outline, and no two alike.
@MainActor
struct HUDPlacementPickerTests {

    private let interior = HUDPlacementIcon.interior

    @Test func theRowsListEveryPlaceExactlyOnceTopToBottom() {
        let listed = Array(HUDPlacementPicker.rows.joined())
        #expect(listed.count == HUDPlacement.allCases.count)
        #expect(Set(listed) == Set(HUDPlacement.allCases))
        #expect(HUDPlacementPicker.rows == [
            [.topLeft, .topCenter, .topRight],
            [.middleLeft, .middleRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ])
    }

    @Test func everyPlacementHasItsOwnName() {
        let names = HUDPlacement.allCases.map(\.displayName)
        #expect(Set(names).count == names.count)
    }

    @Test func eachBarSitsInItsPlacesThirdOfTheScreen() {
        // Independent of the production switch: the table names where each
        // place is, and the icon has to agree with it.
        enum Column { case left, center, right }
        enum Row { case top, middle, bottom }
        let table: [HUDPlacement: (Column, Row)] = [
            .topLeft: (.left, .top), .topCenter: (.center, .top), .topRight: (.right, .top),
            .middleLeft: (.left, .middle), .middleRight: (.right, .middle),
            .bottomLeft: (.left, .bottom), .bottomCenter: (.center, .bottom), .bottomRight: (.right, .bottom),
        ]
        #expect(table.count == HUDPlacement.allCases.count)
        let third = CGSize(width: interior.width / 3, height: interior.height / 3)
        for (placement, (column, row)) in table {
            let bar = HUDPlacementIcon.bar(for: placement)
            switch column {
            case .left: #expect(bar.midX < interior.minX + third.width, "\(placement)")
            case .center: #expect(abs(bar.midX - interior.midX) < 0.01, "\(placement)")
            case .right: #expect(bar.midX > interior.maxX - third.width, "\(placement)")
            }
            switch row {
            case .top: #expect(bar.midY < interior.minY + third.height, "\(placement)")
            case .middle: #expect(abs(bar.midY - interior.midY) < 0.01, "\(placement)")
            case .bottom: #expect(bar.midY > interior.maxY - third.height, "\(placement)")
            }
        }
    }

    @Test func barsOnOneEdgeLineUpSoACornerReadsAsACorner() {
        let bar = HUDPlacementIcon.bar(for:)
        #expect(bar(.topLeft).minX == bar(.middleLeft).minX)
        #expect(bar(.topLeft).minX == bar(.bottomLeft).minX)
        #expect(bar(.topRight).maxX == bar(.middleRight).maxX)
        #expect(bar(.topRight).maxX == bar(.bottomRight).maxX)
        #expect(bar(.topLeft).minY == bar(.topCenter).minY)
        #expect(bar(.topLeft).minY == bar(.topRight).minY)
        #expect(bar(.bottomLeft).maxY == bar(.bottomCenter).maxY)
        #expect(bar(.bottomLeft).maxY == bar(.bottomRight).maxY)
    }

    @Test func theBarIsUprightInTheMiddleOfASideAndFlatElsewhere() {
        for placement in HUDPlacement.allCases {
            let bar = HUDPlacementIcon.bar(for: placement)
            #expect((bar.height > bar.width) == (placement.axis == .vertical), "\(placement)")
        }
    }

    @Test func theBarKeepsTheRealHUDsProportionsAndIsThickEnoughToRead() {
        // Derived from the metrics, so a resized HUD resizes its icon.
        let real = CardMetrics.hudSystemWidth / CardMetrics.hudSystemHeight
        for placement in HUDPlacement.allCases {
            let bar = HUDPlacementIcon.bar(for: placement)
            let long = max(bar.width, bar.height)
            let thick = min(bar.width, bar.height)
            #expect(abs(long / thick - real) < 0.001, "\(placement)")
            #expect(thick >= 1.5, "\(placement)")
        }
    }

    @Test func everyBarStaysInsideTheOutlineClearOfItsStroke() {
        let canvas = CGRect(origin: .zero, size: HUDPlacementIcon.size)
        #expect(canvas.contains(HUDPlacementIcon.screen.insetBy(dx: -HUDPlacementIcon.lineWidth / 2, dy: -HUDPlacementIcon.lineWidth / 2)))
        let clear = interior.insetBy(dx: HUDPlacementIcon.gap, dy: HUDPlacementIcon.gap)
        for placement in HUDPlacement.allCases {
            let bar = HUDPlacementIcon.bar(for: placement)
            #expect(clear.insetBy(dx: -0.001, dy: -0.001).contains(bar), "\(placement)")
        }
    }

    @Test func noTwoPlacesDrawTheSameIcon() {
        let bars = HUDPlacement.allCases.map(HUDPlacementIcon.bar(for:))
        for i in bars.indices {
            for j in bars.indices where j > i {
                #expect(bars[i] != bars[j], "\(HUDPlacement.allCases[i]) / \(HUDPlacement.allCases[j])")
            }
        }
    }

    @Test func theIconIsATemplateTheMenuCanTint() {
        for placement in HUDPlacement.allCases {
            let image = HUDPlacementIcon.image(for: placement)
            #expect(image.isTemplate, "\(placement)")
            #expect(image.size == HUDPlacementIcon.size, "\(placement)")
        }
    }
}
