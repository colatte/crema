import SwiftUI
import Testing
@testable import Crema

/// Everything the scrubber's bar answers as a pure rule: the pointer→seconds
/// mapping, the fill it draws when there is no length to draw, the shape its
/// labels hold, when it counts as a live control — and the look it shares with
/// the HUD bar.
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

    // MARK: - What the bar draws when there is nothing to draw

    @Test func contentWithNoDurationDrawsABareBarInsteadOfAFinishedOne() {
        // The fraction has no denominator, and the row used to invent one —
        // `max(position, 1)` — which is exactly 1 from the first second onward. A
        // radio stream therefore drew a full bar, permanently, and full means
        // "finished" to everyone who has ever seen a player.
        #expect(ScrubberRow.fill(position: 1, duration: nil) == 0)
        #expect(ScrubberRow.fill(position: 4200, duration: nil) == 0)
        // Zero seconds in is the same picture from the other side: a bare track,
        // never a phantom nub (CapsuleTrack.capsuleFillWidth draws that rule).
        #expect(ScrubberRow.fill(position: 0, duration: 180) == 0)
    }

    @Test func aDurationIsTheDenominatorAndTheFractionIsClamped() {
        #expect(ScrubberRow.fill(position: 90, duration: 180) == 0.5)
        #expect(ScrubberRow.fill(position: 180, duration: 180) == 1)
        // A position past the reported duration (the payload's two numbers are
        // sampled apart) fills the bar rather than escaping it.
        #expect(ScrubberRow.fill(position: 400, duration: 180) == 1)
        #expect(ScrubberRow.fill(position: -5, duration: 180) == 0)
        // A zero-length track divides by nothing.
        #expect(ScrubberRow.fill(position: 5, duration: 0) == 0)
    }

    @Test func aLiveStreamKeepsOneLabelShapeInsteadOfGrowingOneMidPlay() {
        // The shape follows the TRACK's length, and live content has none — so it
        // is fixed at m:ss rather than derived from the running position, which
        // would rewrite the label's own width (22.33 → 38.25 pt, measured) the
        // moment a stream on screen crossed an hour and shove the bar beside it.
        #expect(!ScrubberRow.showsHours(duration: nil))
        // With a duration the row still earns hours the ordinary way: an
        // audiobook reads 1:20:00 on both labels, never 5:00 / 1:20:00.
        #expect(ScrubberRow.showsHours(duration: TimeLabel.secondsInAnHour + 1))
        #expect(!ScrubberRow.showsHours(duration: 180))
        #expect(ScrubberRow.showsHours(duration: 4800))
    }

    // MARK: - A dead bar looks dead

    @Test func theRowIsLiveWhileItIsInteractiveOrStillUnderTheFinger() {
        // The truth table, written out rather than recomputed: the row dims and
        // stops tracking together, and the in-flight gesture is what keeps a
        // degraded row live to the end of the drag. Dropping `isEditing` from the
        // rule is the mutation that dims the bar under the finger — and yanks the
        // tracking with it — when a command failure lands mid-drag.
        #expect(ScrubberRow.isLive(interactive: true, isEditing: false))
        #expect(ScrubberRow.isLive(interactive: true, isEditing: true))
        #expect(ScrubberRow.isLive(interactive: false, isEditing: true))
        #expect(!ScrubberRow.isLive(interactive: false, isEditing: false))
    }

    @Test func theSharedDimmingIsActuallyADimming() {
        // Sameness is structural — the bar reads the transport's own constant, so
        // there is no second number to drift. What a test can still catch is the
        // constant being retuned up to 1, which would take the affordance away
        // from every dead control on the surface at once, silently.
        #expect(TransportControls.disabledOpacity < 1)
        #expect(TransportControls.disabledOpacity > 0)
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
