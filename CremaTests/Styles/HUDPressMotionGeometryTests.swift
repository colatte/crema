import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// Where the bar's answer to a key is drawn: the whole bar scaling about its
/// centre while the key is down, and drifting toward an end a press pushes past,
/// against a resistance that grows; and every reach fitting the room it spends —
/// the capsule's inside its row, the filled surface inside its window
/// (docs/DECISIONS.md: the-bar-answers-the-press).
struct HUDPressMotionGeometryTests {

    private let length: CGFloat = 156
    private let raising = HUDPress(kind: .volume, end: .end)
    private let lowering = HUDPress(kind: .volume, end: .start)

    /// The span's two ends in the view's own coordinates.
    private func edges(_ span: (length: CGFloat, center: CGFloat)) -> (low: CGFloat, high: CGFloat) {
        (span.center - span.length / 2, span.center + span.length / 2)
    }

    private func shape(_ press: HUDPress?, axis: Axis = .horizontal, steps: Int = 0) -> HUDPressShape {
        var press = press
        press?.stepsPastEnd = steps
        return HUDPressShape(
            length: length, thickness: CapsuleTrack.trackThickness, axis: axis, press: press,
            ceiling: CapsuleTrack.pressCeiling
        )
    }

    @Test func atRestTheBarSpansItsRow() {
        for axis in [Axis.horizontal, .vertical] {
            let rest = edges(CapsuleTrack.drawnSpan(length: length, shape: shape(nil, axis: axis), axis: axis))
            #expect(rest.low == 0 && rest.high == length, "\(axis)")
        }
    }

    @Test func aHeldKeyScalesTheWholeBarAboutItsCentre() {
        let cases: [(HUDPress, Axis, CGFloat)] = [
            (raising, .horizontal, 1.03), (lowering, .horizontal, 0.96),
            (raising, .vertical, 1.06), (lowering, .vertical, 0.92),
        ]
        for (press, axis, scale) in cases {
            let held = shape(press, axis: axis)
            #expect(abs(held.length - length * scale) < 1e-9, "\(axis) \(press.end)")
            #expect(abs(held.thickness - CapsuleTrack.trackThickness * scale) < 1e-9, "\(axis) \(press.end)")
            #expect(held.shift == 0, "\(axis) \(press.end)")
        }
    }

    @Test func aPushDriftsTheBarTowardTheEndItIsPushedPast() {
        // Horizontal: the full end is the high coordinate, in either language.
        let past = edges(CapsuleTrack.drawnSpan(length: length, shape: shape(raising, steps: 1), axis: .horizontal))
        let held = edges(CapsuleTrack.drawnSpan(length: length, shape: shape(raising), axis: .horizontal))
        #expect(past.high > held.high)
        #expect(past.low > held.low)
        // Upright: the full end is the low coordinate, and a push at the start
        // drifts the bar the other way. Measured against the same key held without
        // a push: the lowering scale alone pulls both ends in further than one
        // push carries them out.
        let span = { (press: HUDPress, steps: Int) in
            edges(CapsuleTrack.drawnSpan(length: length, shape: shape(press, axis: .vertical, steps: steps), axis: .vertical))
        }
        #expect(span(raising, 1).low < span(raising, 0).low)
        #expect(span(lowering, 1).high > span(lowering, 0).high)
    }

    @Test func theFarEndTravelsAndTheNearOneFollows() {
        // UIKit's split of a push: the bar drifts 77% of it and lengthens by 73%,
        // so the far end goes ~114% out while the near one recedes ~40% after it,
        // past whatever the scale adds there once the push is deep enough.
        let filled = CardMetrics.hudSize(for: .horizontal)
        let rest = HUDPressShape(length: filled.width, thickness: filled.height)
        var deep = raising
        deep.stepsPastEnd = 64
        let pushed = HUDPressShape(
            length: filled.width, thickness: filled.height, axis: .horizontal, press: deep,
            ceiling: CardMetrics.hudFilledPressCeiling
        )
        let near = pushed.shift - pushed.length / 2
        let far = pushed.shift + pushed.length / 2
        #expect(far > rest.length / 2)
        #expect(near > -rest.length / 2)
    }

    @Test func eachPressPastTheEndGoesLessFarThanTheOneBefore() {
        let ceiling = CardMetrics.hudFilledPressCeiling
        let steps = (0...12).map { HUDPressShape.overflow(steps: $0, length: 220, ceiling: ceiling) }
        #expect(steps[0] == 0)
        for index in 1..<steps.count {
            #expect(steps[index] > steps[index - 1])
            #expect(steps[index] < ceiling)
            if index > 1 { #expect(steps[index] - steps[index - 1] < steps[index - 1] - steps[index - 2]) }
        }
    }

    @Test func aPushThinsTheBarButNeverToNothing() {
        // UIKit's own rule, the larger of 8% and 4 pt, would leave a 4 pt track
        // nothing; the gentler one keeps it.
        let deep = shape(raising, steps: 1000)
        #expect(deep.thickness < shape(raising).thickness)
        #expect(deep.thickness >= CapsuleTrack.trackThickness * HUDPressShape.squishFactor)
    }

    @Test func theCapsuleReachStaysInsideItsRow() {
        // The far end spends the row's padding or the gap to the glyph, whichever
        // it faces, on the Card and on the Notch alike; past either the bar is
        // cropped by the surface or runs into the glyph. The Card slider's track,
        // the longest the capsule draws, bounds the Notch's too.
        let track = CardMetrics.hudSystemWidth - 2 * CardMetrics.contentPaddingHorizontal
            - CardHUDIndicator.hudIconSlot - CardMetrics.contentGap
        let room = min(
            CardMetrics.contentPaddingHorizontal, CardMetrics.contentGap,
            NotchMetrics.contentPaddingHorizontal, NotchMetrics.hudGap
        )
        for axis in [Axis.horizontal, .vertical] {
            #expect(HUDPressShape.reach(length: track, axis: axis, ceiling: CapsuleTrack.pressCeiling) <= room, "\(axis)")
        }
        let thickest = CapsuleTrack.engagedThickness * HUDPressShape.verticalRaiseScale
        #expect(thickest < CapsuleTrack.trackHitHeight)
    }

    @Test func theSmallestFillIsAsThickAsTheBarItSitsIn() {
        let sliver = 0.001
        #expect(CapsuleTrack.capsuleFillLength(for: sliver, trackLength: length) == CapsuleTrack.trackThickness)
        #expect(CapsuleTrack.capsuleFillLength(
            for: sliver, trackLength: length, thickness: CapsuleTrack.engagedThickness
        ) == CapsuleTrack.engagedThickness)
        #expect(CapsuleTrack.capsuleFillLength(for: 0, trackLength: length, thickness: CapsuleTrack.engagedThickness) == 0)
    }

    @Test func theFilledSurfaceRestsWhereItsRuleSaysAndGrowsOnlyUnderADrag() {
        for axis in [Axis.horizontal, .vertical] {
            let rest = CardMetrics.hudSize(for: axis)
            let still = CardMetrics.hudFilledPressed(rest, axis: axis, engaged: false, press: nil)
            #expect(still.size == rest && still.offset == .zero, "\(axis)")
            let grown = CardMetrics.hudFilledPressed(rest, axis: axis, engaged: true, press: nil)
            let growth = CardMetrics.hudFilledEngagedGrowth
            #expect(grown.size == (axis == .horizontal
                    ? CGSize(width: rest.width, height: rest.height + growth)
                    : CGSize(width: rest.width + growth, height: rest.height)), "\(axis)")
        }
    }

    @Test func theFilledSurfaceScalesAboutWhereItRests() {
        // The view centres the surface across its window and hangs it from the
        // top: a horizontal bar needs no move to stay centred, an upright one
        // takes back half its growth.
        let horizontal = CardMetrics.hudSize(for: .horizontal)
        let wide = CardMetrics.hudFilledPressed(horizontal, axis: .horizontal, engaged: false, press: raising)
        #expect(wide.offset == .zero)
        #expect(wide.size.width > horizontal.width)

        let upright = CardMetrics.hudSize(for: .vertical)
        let tall = CardMetrics.hudFilledPressed(upright, axis: .vertical, engaged: false, press: raising)
        #expect(abs(tall.offset.height + (tall.size.height - upright.height) / 2) < 1e-9)
    }

    @Test func theFilledSurfaceDriftsTowardThePushOnEitherAxis() {
        var pushed = raising
        pushed.stepsPastEnd = 1
        let horizontal = CardMetrics.hudFilledPressed(
            CardMetrics.hudSize(for: .horizontal), axis: .horizontal, engaged: false, press: pushed
        )
        #expect(horizontal.offset.width > 0)
        let upright = CardMetrics.hudFilledPressed(CardMetrics.hudSize(for: .vertical), axis: .vertical, engaged: false, press: pushed)
        let rest = CardMetrics.hudSize(for: .vertical)
        // Up: the surface's centre sits above where it rests.
        #expect(upright.offset.height + upright.size.height / 2 < rest.height / 2)
    }

    @Test func theFilledSurfaceFitsTheRoomItsWindowsKeep() {
        // Below a horizontal bar, the open spring's headroom takes the drag's
        // growth and the press's scale together.
        let horizontal = CardMetrics.hudSize(for: .horizontal)
        let grown = (horizontal.height + CardMetrics.hudFilledEngagedGrowth) * HUDPressShape.horizontalRaiseScale
        #expect(grown - horizontal.height <= SurfaceAnimation.overshootHeadroom)
        // The card's own window, where the HUD sits on the card's spot, keeps the
        // reach sideways already.
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let hud = Style.card.frame(for: .hud(SystemHUD(kind: .volume, value: 1)), on: geometry)
        let window = Style.card.windowFrame(on: geometry)
        let reach = CardMetrics.hudPressRoom(for: .horizontal)
        #expect(window.minX <= hud.minX - reach)
        #expect(window.maxX >= hud.maxX + reach)
    }

    @Test func aPlacedFilledHUDNeverLeavesTheScreen() {
        // A corner placement's far end faces the screen's edge, the margin away;
        // an upright bar's ends face the screen's middle.
        #expect(CardMetrics.hudPressRoom(for: .horizontal) <= CardMetrics.hudEdgeMargin)
    }

    @Test func reduceMotionStillsBoth() {
        #expect(SurfaceAnimation.allowsHUDPressMotion(reduceMotion: false))
        #expect(!SurfaceAnimation.allowsHUDPressMotion(reduceMotion: true))
    }
}
