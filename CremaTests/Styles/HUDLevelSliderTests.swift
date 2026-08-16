import SwiftUI
import Testing
@testable import Crema

/// The level indicator's mechanics extracted pure: drag fraction (with the RTL
/// mirror), fill width, spring gating, the hover knob's visibility/position and
/// the Classic segment fill. These pins are new with the capsule — nothing
/// pinned any interaction attribute of the old stock-Slider variant.
struct HUDLevelSliderTests {

    @Test func fractionClampsAtBothEnds() {
        #expect(HUDLevelSlider.fraction(atX: -10, trackWidth: 100, layoutDirection: .leftToRight) == 0)
        #expect(HUDLevelSlider.fraction(atX: 110, trackWidth: 100, layoutDirection: .leftToRight) == 1)
        #expect(HUDLevelSlider.fraction(atX: 25, trackWidth: 100, layoutDirection: .leftToRight) == 0.25)
    }

    @Test func fractionIsNilOnDegenerateWidth() {
        #expect(HUDLevelSlider.fraction(atX: 10, trackWidth: 0, layoutDirection: .leftToRight) == nil)
    }

    @Test func fractionMirrorsUnderRightToLeft() {
        // Gesture coordinates are physical and do not flip with the layout;
        // the leading-anchored fill does — so the fraction must mirror.
        #expect(HUDLevelSlider.fraction(atX: 25, trackWidth: 100, layoutDirection: .rightToLeft) == 0.75)
    }

    @Test func fillWidthClampsTheValue() {
        #expect(CapsuleTrack.fillWidth(for: -0.5, trackWidth: 100) == 0)
        #expect(CapsuleTrack.fillWidth(for: 1.5, trackWidth: 100) == 100)
        #expect(CapsuleTrack.fillWidth(for: 0.5, trackWidth: 100) == 50)
    }

    @Test func curvedFillFloorsAtTheTrackThicknessButKeepsZeroEmpty() {
        // The curved fill (deliberate deviation from the native flat cut —
        // docs/DECISIONS.md: hud-capsule-track): a sub-thickness width would
        // draw a squashed vertical oval, so the floor is the 4 pt thickness (a
        // circle-capped nub); exactly 0% stays empty — no phantom dot.
        #expect(CapsuleTrack.capsuleFillWidth(for: 0, trackWidth: 100) == 0)
        #expect(CapsuleTrack.capsuleFillWidth(for: 0.01, trackWidth: 100) == HUDLevelSlider.trackThickness)
        #expect(CapsuleTrack.capsuleFillWidth(for: 0.5, trackWidth: 100) == 50)
        #expect(CapsuleTrack.capsuleFillWidth(for: 1, trackWidth: 100) == 100)
        // Above the floor the curved width IS the proportional width.
        #expect(CapsuleTrack.capsuleFillWidth(for: 0.1, trackWidth: 100) == CapsuleTrack.fillWidth(for: 0.1, trackWidth: 100))
    }

    @Test func springSuspendsWhileEditingAndUnderReduceMotion() {
        #expect(HUDLevelSlider.animatesLevel(isEditing: false, reduceMotion: false))
        #expect(!HUDLevelSlider.animatesLevel(isEditing: true, reduceMotion: false))
        #expect(!HUDLevelSlider.animatesLevel(isEditing: false, reduceMotion: true))
    }

    @Test func knobTravelsTheInsetTrackAndMirrors() {
        // The native thumb mapping: halfKnob + value × (width − knob). At ½ it
        // sits exactly on the fill boundary; off-center it deviates by at most
        // halfKnob, always over its own body (pinned below), mirrored under RTL.
        #expect(CapsuleTrack.knobCenterX(for: 0.5, trackWidth: 100, layoutDirection: .leftToRight) == 50)
        #expect(CapsuleTrack.knobCenterX(for: 0.25, trackWidth: 100, layoutDirection: .leftToRight) == 29.375)
        #expect(CapsuleTrack.knobCenterX(for: 0.25, trackWidth: 100, layoutDirection: .rightToLeft) == 70.625)
    }

    @Test func knobStaysInsideTheRowAtTheExtremes() {
        // Half the 17.5 pt knob: it must never exit the row (a slider knob,
        // not a floating pill), mirrored under RTL.
        #expect(CapsuleTrack.knobCenterX(for: 0, trackWidth: 100, layoutDirection: .leftToRight) == 8.75)
        #expect(CapsuleTrack.knobCenterX(for: 1, trackWidth: 100, layoutDirection: .leftToRight) == 91.25)
        #expect(CapsuleTrack.knobCenterX(for: 0, trackWidth: 100, layoutDirection: .rightToLeft) == 91.25)
    }

    @Test func knobNeverFreezesNearTheExtremes() {
        // The hardware-reported jam, pinned dead: the old boundary-clamp
        // mapping held the knob at halfKnob for the whole first (and last)
        // ~halfKnob of fill travel, so a drag near 0/100% moved the value and
        // the fill while the knob stood still. The inset-travel mapping is
        // strictly monotonic across the entire scale.
        let values: [Double] = [0, 0.02, 0.05, 0.08, 0.5, 0.92, 0.95, 0.98, 1]
        let centers = values.map {
            CapsuleTrack.knobCenterX(for: $0, trackWidth: 100, layoutDirection: .leftToRight)
        }
        #expect(centers == centers.sorted())
        #expect(Set(centers).count == centers.count, "equal centers = a dead zone the drag can feel")
    }

    @Test func fillBoundaryStaysUnderTheKnobBody() {
        // The inset mapping trades exact boundary-centering for continuous
        // response; the trade is safe because the DRAWN boundary — the
        // floored capsuleFillWidth, the edge the eye actually sees — never
        // escapes the knob's own 17.5 pt body (|boundary − center| ≤ halfKnob).
        for value in stride(from: 0.0, through: 1.0, by: 0.05) {
            let center = CapsuleTrack.knobCenterX(for: value, trackWidth: 100, layoutDirection: .leftToRight)
            let boundary = CapsuleTrack.capsuleFillWidth(for: value, trackWidth: 100)
            #expect(abs(boundary - center) <= 8.75 + 0.0001, "value \(value)")
        }
        // A sub-floor value (the nub drawn at the 4 pt floor) stays covered too.
        let subFloorCenter = CapsuleTrack.knobCenterX(for: 0.01, trackWidth: 100, layoutDirection: .leftToRight)
        #expect(abs(CapsuleTrack.capsuleFillWidth(for: 0.01, trackWidth: 100) - subFloorCenter) <= 8.75)
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
