import SwiftUI
import Testing
@testable import Crema

/// The scrubber's pointer→seconds rule, and the contract it now shares with the
/// HUD bar.
///
/// It had none of this: the row was a stock `Slider`, so its mapping was
/// AppKit's and its look was the system control's — a thumb always visible,
/// tinted with the artwork accent. Two rows above it in the lock card sat the
/// HUD's own bar, thumbless and white, measured off the Tahoe banner and
/// recorded as a decision. One card, two bars, opposite rules.
struct ScrubberTrackTests {

    private let ltr = LayoutDirection.leftToRight

    @Test func theEndsOfTheRowReachTheEndsOfTheTrack() {
        // The mapping stays over the FULL width — deliberately NOT inset by the
        // knob's half-width the way the knob's own travel is. A tap on the last
        // pixel has to seek to the end, or the final seconds are unreachable.
        #expect(ScrubberRow.position(atX: 0, width: 200, span: 180, layoutDirection: ltr) == 0)
        #expect(ScrubberRow.position(atX: 200, width: 200, span: 180, layoutDirection: ltr) == 180)
        #expect(ScrubberRow.position(atX: 100, width: 200, span: 180, layoutDirection: ltr) == 90)
    }

    @Test func aPointerPastEitherEndClampsRatherThanSeeksOutOfBounds() {
        // A drag continues past the row's edge — the gesture keeps reporting.
        #expect(ScrubberRow.position(atX: -40, width: 200, span: 180, layoutDirection: ltr) == 0)
        #expect(ScrubberRow.position(atX: 900, width: 200, span: 180, layoutDirection: ltr) == 180)
    }

    @Test func rightToLeftMirrorsTheRow() {
        let rtl = LayoutDirection.rightToLeft
        #expect(ScrubberRow.position(atX: 0, width: 200, span: 180, layoutDirection: rtl) == 180)
        #expect(ScrubberRow.position(atX: 200, width: 200, span: 180, layoutDirection: rtl) == 0)
    }

    @Test func aTrackWithNoLengthSeeksNowhereInsteadOfDividingByZero() {
        // Live content reports no duration, and the row still renders.
        #expect(ScrubberRow.position(atX: 50, width: 200, span: 0, layoutDirection: ltr) == 0)
        #expect(ScrubberRow.position(atX: 50, width: 0, span: 180, layoutDirection: ltr) == 0)
    }

    // MARK: - The look both bars now share

    @Test func theBarIsWhiteRatherThanTintedByTheCover() {
        // The decision the scrubber never adopted (docs/DECISIONS.md:
        // hud-capsule-track): the fill is a control, and a control reads white.
        // The cover's tone still reaches the surface around it, never the bar.
        #expect(CapsuleTrack.fillColor == Color.white)
    }

    @Test func thereIsNoKnobUntilThePointerIsOnTheBar() {
        // "A pontinha no final" — reported from the lock screen, and correct:
        // the affordance is on demand, exactly as Control Center does it. The
        // knob has a real size, so its absence at rest is a decision rather than
        // a thing that happens to be invisible.
        #expect(CapsuleTrack.knobSize.width > 0)
        #expect(CapsuleTrack.knobSize.height > 0)
        // Both bars ask the same question with the same shape: hovered OR
        // dragging. The HUD adds its appearance gate on top.
        #expect(HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: true, isEditing: false))
        #expect(HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: false, isEditing: true))
        #expect(!HUDLevelSlider.showsKnob(appearance: .capsule, isHovered: false, isEditing: false))
    }

    @Test func theSmallestVisibleFillIsARoundNubAndZeroIsBare() {
        // Shared with the HUD, and worth restating from the scrubber's side: a
        // track one second into a song must not draw a squashed vertical oval,
        // and a track at zero must not draw a phantom dot.
        #expect(CapsuleTrack.capsuleFillWidth(for: 0, trackWidth: 200) == 0)
        #expect(CapsuleTrack.capsuleFillWidth(for: 0.001, trackWidth: 200) == CapsuleTrack.trackThickness)
        #expect(CapsuleTrack.capsuleFillWidth(for: 0.5, trackWidth: 200) == 100)
    }
}
