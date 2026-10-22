import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// Where the bar's answer to a press is drawn: the pulled end travels and the
/// other stays put, and every growth fits the room it spends — the capsule's
/// inside its row, the filled surface inside its window
/// (docs/DECISIONS.md: the-bar-answers-the-press).
struct HUDPressMotionGeometryTests {

    private let length: CGFloat = 156

    /// The span's two ends in the view's own coordinates.
    private func edges(_ span: (length: CGFloat, center: CGFloat)) -> (low: CGFloat, high: CGFloat) {
        (span.center - span.length / 2, span.center + span.length / 2)
    }

    @Test func atRestTheBarSpansItsRow() {
        for axis in [Axis.horizontal, .vertical] {
            let rest = edges(CapsuleTrack.drawnSpan(length: length, overreach: 0, axis: axis))
            #expect(rest.low == 0 && rest.high == length, "\(axis)")
        }
    }

    @Test func onlyThePulledEndTravels() {
        let pull = CapsuleTrack.pushOverreach
        // Horizontal: the start is leading, the low coordinate, in either language.
        let rightward = edges(CapsuleTrack.drawnSpan(length: length, overreach: pull, axis: .horizontal))
        #expect(rightward.low == 0 && rightward.high == length + pull)
        let leftward = edges(CapsuleTrack.drawnSpan(length: length, overreach: -pull, axis: .horizontal))
        #expect(leftward.low == -pull && leftward.high == length)
        // Upright: the start is the bottom, the high coordinate.
        let upward = edges(CapsuleTrack.drawnSpan(length: length, overreach: pull, axis: .vertical))
        #expect(upward.low == -pull && upward.high == length)
        let downward = edges(CapsuleTrack.drawnSpan(length: length, overreach: -pull, axis: .vertical))
        #expect(downward.low == 0 && downward.high == length + pull)
    }

    @Test func eachEndPullsItsOwnWay() {
        #expect(CapsuleTrack.overreach(for: nil) == 0)
        #expect(CapsuleTrack.overreach(for: .end) == CapsuleTrack.pushOverreach)
        #expect(CapsuleTrack.overreach(for: .start) == -CapsuleTrack.pushOverreach)
    }

    @Test func theCapsulePullStaysInsideItsRow() {
        // The far end spends the row's padding, the near one the gap to the glyph,
        // on the Card and on the Notch alike; past either the pull is cropped by
        // the surface or runs into the glyph.
        let pull = CapsuleTrack.pushOverreach
        #expect(pull < CardMetrics.contentPaddingHorizontal)
        #expect(pull < CardMetrics.contentGap)
        #expect(pull < NotchMetrics.contentPaddingHorizontal)
        #expect(pull < NotchMetrics.hudGap)
        #expect(CapsuleTrack.engagedThickness < CapsuleTrack.trackHitHeight)
    }

    @Test func theSmallestFillIsAsThickAsTheBarItSitsIn() {
        let sliver = 0.001
        #expect(CapsuleTrack.capsuleFillLength(for: sliver, trackLength: length) == CapsuleTrack.trackThickness)
        #expect(CapsuleTrack.capsuleFillLength(
            for: sliver, trackLength: length, thickness: CapsuleTrack.engagedThickness
        ) == CapsuleTrack.engagedThickness)
        #expect(CapsuleTrack.capsuleFillLength(for: 0, trackLength: length, thickness: CapsuleTrack.engagedThickness) == 0)
    }

    @Test func theFilledSurfaceKeepsItsUnpulledEndWhereItWas() {
        // The view centres the surface across the window and hangs it from the top.
        for axis in [Axis.horizontal, .vertical] {
            let rest = CardMetrics.hudSize(for: axis)
            for end in [HUDPush.End.start, .end] {
                let pulled = CardMetrics.hudFilledPressedSize(rest, axis: axis, engaged: false, push: end)
                let shift = CardMetrics.hudFilledPressOffset(axis: axis, push: end)
                if axis == .horizontal {
                    let leading = -pulled.width / 2 + shift.width
                    let trailing = pulled.width / 2 + shift.width
                    if end == .end {
                        #expect(leading == -rest.width / 2)
                        #expect(trailing == rest.width / 2 + CardMetrics.hudFilledPushOverreach)
                    } else {
                        #expect(trailing == rest.width / 2)
                        #expect(leading == -rest.width / 2 - CardMetrics.hudFilledPushOverreach)
                    }
                } else {
                    let top = shift.height
                    let bottom = pulled.height + shift.height
                    if end == .end {
                        #expect(bottom == rest.height)
                        #expect(top == -CardMetrics.hudFilledPushOverreach)
                    } else {
                        #expect(top == 0)
                        #expect(bottom == rest.height + CardMetrics.hudFilledPushOverreach)
                    }
                }
            }
        }
    }

    @Test func theFilledSurfaceGrowsAcrossTheBarOnlyWhileInUse() {
        for axis in [Axis.horizontal, .vertical] {
            let rest = CardMetrics.hudSize(for: axis)
            #expect(CardMetrics.hudFilledPressedSize(rest, axis: axis, engaged: false, push: nil) == rest)
            let grown = CardMetrics.hudFilledPressedSize(rest, axis: axis, engaged: true, push: nil)
            let growth = CardMetrics.hudFilledEngagedGrowth
            #expect(grown == (axis == .horizontal
                    ? CGSize(width: rest.width, height: rest.height + growth)
                    : CGSize(width: rest.width + growth, height: rest.height)))
        }
    }

    @Test func theFilledSurfaceFitsTheRoomItsWindowKeeps() {
        // Sideways and below, the open spring's headroom; above, only the upright
        // window's own room, and exactly the pull it exists for.
        let headroom = SurfaceAnimation.overshootHeadroom
        #expect(CardMetrics.hudFilledPushOverreach <= headroom)
        #expect(CardMetrics.hudFilledEngagedGrowth <= headroom)
        #expect(CardMetrics.hudTopHeadroom(for: .horizontal) == 0)
        #expect(-CardMetrics.hudFilledPressOffset(axis: .vertical, push: .end).height
            == CardMetrics.hudTopHeadroom(for: .vertical))
    }

    @Test func reduceMotionStillsBoth() {
        #expect(SurfaceAnimation.allowsHUDPressMotion(reduceMotion: false))
        #expect(!SurfaceAnimation.allowsHUDPressMotion(reduceMotion: true))
    }
}
