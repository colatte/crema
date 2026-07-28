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
        #expect(HUDLevelSlider.fillWidth(for: -0.5, trackWidth: 100) == 0)
        #expect(HUDLevelSlider.fillWidth(for: 1.5, trackWidth: 100) == 100)
        #expect(HUDLevelSlider.fillWidth(for: 0.5, trackWidth: 100) == 50)
    }

    @Test func springSuspendsWhileEditingAndUnderReduceMotion() {
        #expect(HUDLevelSlider.animatesLevel(isEditing: false, reduceMotion: false))
        #expect(!HUDLevelSlider.animatesLevel(isEditing: true, reduceMotion: false))
        #expect(!HUDLevelSlider.animatesLevel(isEditing: false, reduceMotion: true))
    }

    @Test func knobRidesTheFillBoundaryAndMirrors() {
        #expect(HUDLevelSlider.knobCenterX(for: 0.25, trackWidth: 100, layoutDirection: .leftToRight) == 25)
        #expect(HUDLevelSlider.knobCenterX(for: 0.25, trackWidth: 100, layoutDirection: .rightToLeft) == 75)
    }

    @Test func knobClampsInsideTheRowAtTheExtremes() {
        // Half the 17.5 pt knob: it must never exit the row (a slider knob,
        // not a floating pill), mirrored under RTL.
        #expect(HUDLevelSlider.knobCenterX(for: 0, trackWidth: 100, layoutDirection: .leftToRight) == 8.75)
        #expect(HUDLevelSlider.knobCenterX(for: 1, trackWidth: 100, layoutDirection: .leftToRight) == 91.25)
        #expect(HUDLevelSlider.knobCenterX(for: 0, trackWidth: 100, layoutDirection: .rightToLeft) == 91.25)
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
        #expect(SurfaceAnimation.knobReveal(reduceMotion: true) == nil)
        #expect(SurfaceAnimation.knobReveal(reduceMotion: false) != nil)
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
        // into the ninth segment fills it halfway BY WIDTH (design-reference
        // §4.4 — the pre-Tahoe bezel's partial-segment behavior).
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
