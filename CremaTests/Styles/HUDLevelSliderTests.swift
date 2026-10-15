import SwiftUI
import Testing
@testable import Crema

/// The level indicator's mechanics extracted pure: drag fraction (with the RTL
/// mirror and the upright bar's bottom start), fill length, spring gating, the
/// hover knob's visibility/position and the Classic segment fill.
struct HUDLevelSliderTests {

    @Test func fractionClampsAtBothEnds() {
        #expect(CapsuleTrack.fraction(at: -10, trackLength: 100, reversed: false) == 0)
        #expect(CapsuleTrack.fraction(at: 110, trackLength: 100, reversed: false) == 1)
        #expect(CapsuleTrack.fraction(at: 25, trackLength: 100, reversed: false) == 0.25)
    }

    @Test func fractionIsNilOnDegenerateLength() {
        #expect(CapsuleTrack.fraction(at: 10, trackLength: 0, reversed: false) == nil)
    }

    @Test func fractionMirrorsUnderRightToLeft() {
        // Gesture coordinates are physical and do not flip with the layout;
        // the leading-anchored fill does — so the fraction must mirror.
        let reversed = CapsuleTrack.runsReversed(axis: .horizontal, layoutDirection: .rightToLeft)
        #expect(reversed)
        #expect(CapsuleTrack.fraction(at: 25, trackLength: 100, reversed: reversed) == 0.75)
        #expect(!CapsuleTrack.runsReversed(axis: .horizontal, layoutDirection: .leftToRight))
    }

    @Test func anUprightBarStartsAtTheBottomInEveryLanguage() {
        // Kills an upright bar that follows the reading direction: a level rises
        // from the bottom whether the interface runs left to right or right to
        // left, and the view's y grows downward, so the bottom is the far end.
        #expect(CapsuleTrack.runsReversed(axis: .vertical, layoutDirection: .leftToRight))
        #expect(CapsuleTrack.runsReversed(axis: .vertical, layoutDirection: .rightToLeft))
    }

    @Test func anUprightBarReadsTheLevelFromTheBottom() {
        // y = 0 is the TOP of the bar: a touch there is full, at the bottom empty.
        let reversed = CapsuleTrack.runsReversed(axis: .vertical, layoutDirection: .leftToRight)
        #expect(CapsuleTrack.fraction(at: 0, trackLength: 200, reversed: reversed) == 1)
        #expect(CapsuleTrack.fraction(at: 200, trackLength: 200, reversed: reversed) == 0)
        #expect(CapsuleTrack.fraction(at: 150, trackLength: 200, reversed: reversed) == 0.25)
    }

    @Test func eachAxisHelperReadsTheSideOfTheTrackItsAxisNames() {
        // The pure per-axis helpers: an upright track takes its length from the
        // height, its drag from y, its knob centered across the width and long
        // along the track, and its fill from the bottom; a flat one the transpose.
        // Whether the view routes every axis choice through them is not read here.
        let size = CGSize(width: 36, height: 210)
        let pointer = CGPoint(x: 5, y: 150)
        #expect(CapsuleTrack.length(of: size, axis: .vertical) == 210)
        #expect(CapsuleTrack.length(of: size, axis: .horizontal) == 36)
        #expect(CapsuleTrack.coordinate(of: pointer, axis: .vertical) == 150)
        #expect(CapsuleTrack.coordinate(of: pointer, axis: .horizontal) == 5)
        #expect(CapsuleTrack.point(along: 100, centeredIn: size, axis: .vertical) == CGPoint(x: 18, y: 100))
        #expect(CapsuleTrack.point(along: 100, centeredIn: size, axis: .horizontal) == CGPoint(x: 100, y: 105))
        #expect(CapsuleTrack.knobFrame(axis: .horizontal) == CapsuleTrack.knobSize)
        #expect(CapsuleTrack.knobFrame(axis: .vertical) == CGSize(width: 14, height: 17.5))
        // The layout start agrees with the coordinate start: an upright fill grows
        // from the bottom, where its drag reads zero.
        #expect(CapsuleTrack.startAlignment(axis: .vertical) == .bottom)
        #expect(CapsuleTrack.startEdge(axis: .vertical) == .bottom)
        #expect(CapsuleTrack.startAlignment(axis: .horizontal) == .leading)
        #expect(CapsuleTrack.startEdge(axis: .horizontal) == .leading)
    }

    @Test func fillLengthClampsTheValue() {
        #expect(CapsuleTrack.fillLength(for: -0.5, trackLength: 100) == 0)
        #expect(CapsuleTrack.fillLength(for: 1.5, trackLength: 100) == 100)
        #expect(CapsuleTrack.fillLength(for: 0.5, trackLength: 100) == 50)
    }

    @Test func curvedFillFloorsAtTheTrackThicknessButKeepsZeroEmpty() {
        // The curved fill (deliberate deviation from the native flat cut —
        // docs/DECISIONS.md: hud-capsule-track): a sub-thickness length would
        // draw a squashed oval across the track, so the floor is the 4 pt
        // thickness (a circle-capped nub); exactly 0% stays empty — no phantom dot.
        #expect(CapsuleTrack.capsuleFillLength(for: 0, trackLength: 100) == 0)
        #expect(CapsuleTrack.capsuleFillLength(for: 0.01, trackLength: 100) == HUDLevelSlider.trackThickness)
        #expect(CapsuleTrack.capsuleFillLength(for: 0.5, trackLength: 100) == 50)
        #expect(CapsuleTrack.capsuleFillLength(for: 1, trackLength: 100) == 100)
        // Above the floor the curved length IS the proportional length.
        #expect(CapsuleTrack.capsuleFillLength(for: 0.1, trackLength: 100) == CapsuleTrack.fillLength(for: 0.1, trackLength: 100))
    }

    @Test func springSuspendsWhileEditingAndUnderReduceMotion() {
        #expect(HUDLevelSlider.levelAnimation(isEditing: false, reduceMotion: false) == SurfaceAnimation.hudLevel)
        #expect(HUDLevelSlider.levelAnimation(isEditing: true, reduceMotion: false) == nil)
        #expect(HUDLevelSlider.levelAnimation(isEditing: false, reduceMotion: true) == nil)
    }

    @Test func knobTravelsTheInsetTrackAndMirrors() {
        // The native thumb mapping: halfKnob + value × (length − knob). At ½ it
        // sits exactly on the fill boundary; off-center it deviates by at most
        // halfKnob, always over its own body (pinned below), mirrored when the
        // bar starts at the far end.
        #expect(CapsuleTrack.knobCenter(for: 0.5, trackLength: 100, reversed: false) == 50)
        #expect(CapsuleTrack.knobCenter(for: 0.25, trackLength: 100, reversed: false) == 29.375)
        #expect(CapsuleTrack.knobCenter(for: 0.25, trackLength: 100, reversed: true) == 70.625)
    }

    @Test func knobStaysInsideTheRowAtTheExtremes() {
        // Half the 17.5 pt knob: it must never exit the row (a slider knob,
        // not a floating pill), mirrored when the bar starts at the far end.
        #expect(CapsuleTrack.knobCenter(for: 0, trackLength: 100, reversed: false) == 8.75)
        #expect(CapsuleTrack.knobCenter(for: 1, trackLength: 100, reversed: false) == 91.25)
        #expect(CapsuleTrack.knobCenter(for: 0, trackLength: 100, reversed: true) == 91.25)
    }

    @Test func anUprightKnobRestsAtTheBottomAtZero() {
        // The upright HUD is the transposed 210 pt strip: at 0 the knob sits half
        // its length above the bottom edge, at 1 the same distance below the top.
        let reversed = CapsuleTrack.runsReversed(axis: .vertical, layoutDirection: .leftToRight)
        #expect(CapsuleTrack.knobCenter(for: 0, trackLength: 210, reversed: reversed) == 210 - 8.75)
        #expect(CapsuleTrack.knobCenter(for: 1, trackLength: 210, reversed: reversed) == 8.75)
    }

    @Test func knobNeverFreezesNearTheExtremes() {
        // A boundary clamp holds the knob at halfKnob for the first and last
        // ~halfKnob of fill travel — the jam seen on hardware: a drag near
        // 0/100% moves the value and the fill while the knob stands still. The
        // inset-travel mapping is strictly monotonic across the entire scale.
        let values: [Double] = [0, 0.02, 0.05, 0.08, 0.5, 0.92, 0.95, 0.98, 1]
        let centers = values.map {
            CapsuleTrack.knobCenter(for: $0, trackLength: 100, reversed: false)
        }
        #expect(centers == centers.sorted())
        #expect(Set(centers).count == centers.count, "equal centers = a dead zone the drag can feel")
    }

    @Test func fillBoundaryStaysUnderTheKnobBody() {
        // The inset mapping trades exact boundary-centering for continuous
        // response; the trade is safe because the DRAWN boundary — the
        // floored capsuleFillLength, the edge the eye actually sees — never
        // escapes the knob's own 17.5 pt body (|boundary − center| ≤ halfKnob).
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            let center = CapsuleTrack.knobCenter(for: value, trackLength: 100, reversed: false)
            let boundary = CapsuleTrack.capsuleFillLength(for: value, trackLength: 100)
            #expect(abs(boundary - center) <= 8.75 + 0.0001, "value \(value)")
        }
        // A sub-floor value (the nub drawn at the 4 pt floor) stays covered too.
        let subFloorCenter = CapsuleTrack.knobCenter(for: 0.01, trackLength: 100, reversed: false)
        #expect(abs(CapsuleTrack.capsuleFillLength(for: 0.01, trackLength: 100) - subFloorCenter) <= 8.75)
    }

    @Test func knobFollowsThePointerOrAnActiveDragAndOnlyOnTheCapsule() {
        // The affordance-on-demand contract (docs/DECISIONS.md:
        // hud-capsule-track): clean bar at rest, knob under the pointer, and a
        // drag keeps its knob even if it wanders off the surface.
        #expect(HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: true, isEditing: false))
        #expect(HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: false, isEditing: true))
        #expect(!HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: false, isEditing: false))
        #expect(!HUDLevelSlider.showsKnob(appearance: .segmented, isHovered: true, isEditing: true))
        #expect(!HUDLevelSlider.showsKnob(appearance: .filled, isHovered: true, isEditing: true))
    }

    @Test func knobRevealFadesOnlyWithoutReduceMotion() {
        #expect(CapsuleTrack.knobReveal(reduceMotion: true) == nil)
        #expect(CapsuleTrack.knobReveal(reduceMotion: false) != nil)
    }

    @Test func cardPickerChoiceMapsToTheRightBody() {
        #expect(HUDLevelSlider.appearance(for: .slider) == .capsule)
        #expect(HUDLevelSlider.appearance(for: .filled) == .filled)
    }

    @Test func segmentRunFitsTheClassicBudget() {
        // 16×7.5 + 15×2 = 150 pt inside Classic's 200 − 2×(16+8) = 152 pt
        // inner width — pinned so a future padding change cannot silently
        // clip a segment.
        let run: CGFloat = 16 * 7.5 + 15 * 2
        let budget = ClassicMetrics.hud.width - 2 * (ClassicMetrics.contentPadding + 8)
        #expect(run <= budget)
    }

    @Test func segmentsFillByWidthWithAPartialBoundary() {
        // 50% = 8 of 16 segments: indices 0-7 full, 8-15 empty; a value half
        // into the ninth segment fills it halfway BY WIDTH (the pre-Tahoe
        // bezel's partial-segment behavior).
        #expect(HUDLevelSlider.segmentFill(index: 7, value: 0.5) == 1)
        #expect(HUDLevelSlider.segmentFill(index: 8, value: 0.5) == 0)
        #expect(HUDLevelSlider.segmentFill(index: 8, value: 8.5 / 16) == 0.5)
        #expect(HUDLevelSlider.segmentFill(index: 0, value: 0) == 0)
        #expect(HUDLevelSlider.segmentFill(index: 15, value: 1) == 1)
    }

    @Test func hitRowMatchesTheStockSliderHeight() {
        // 16 pt is the measured height of the stock Slider this capsule
        // replaces: the drag target must not regress and no surrounding
        // layout may move.
        #expect(HUDLevelSlider.trackHitHeight == 16)
    }
}
