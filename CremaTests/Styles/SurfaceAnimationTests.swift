import CoreGraphics
import Foundation
import Testing
@testable import Crema

/// Pins the couplings between the calibratable animation values and the fixed
/// window/click machinery — every value invites hardware retuning, and these
/// are the retunes that would silently break geometry the tests otherwise
/// never see.
struct SurfaceAnimationTests {

    @Test func overshootHeadroomContainsTheOpenSpringsPeak() {
        // A critically underdamped spring overshoots by exp(-ζπ/√(1-ζ²)) of the
        // travelled delta; the fixed window only has `overshootHeadroom` of
        // room past the expanded frame before the morph clips at its edge.
        let damping = SurfaceAnimation.openDamping
        let overshootFraction = exp(-damping * .pi / (1 - damping * damping).squareRoot())

        let deltas: [CGFloat] = [
            NotchMetrics.expandedDrop - NotchMetrics.compactDrop,
            CardMetrics.expanded.height - CardMetrics.compact.height,
            // Largest per-side width travels of the hugging surface (the
            // surface is center-anchored, so each side moves half the delta):
            // a track change morphing a floor-hugging compact to the ceiling,
            // and a short-title hover expand crossing floors.
            (CardMetrics.compactMaxWidth - CardMetrics.compactMinWidth) / 2,
            (CardMetrics.expandedMinWidth - CardMetrics.compactMinWidth) / 2,
        ]
        for delta in deltas {
            #expect(overshootFraction * delta <= SurfaceAnimation.overshootHeadroom)
        }
    }

    // MARK: - Geometry provenance (appear/disappear snaps, morph between visible)

    @Test func appearanceFromHiddenSnapsGeometry() {
        // Either side empty ⇒ nil: the frame/radius jump to the final layout and
        // only the opacity fades. Covers empty→hud and empty→compact.
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: true, toEmpty: false, expanding: false, reduceMotion: false) == nil)
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: true, toEmpty: false, expanding: true, reduceMotion: false) == nil)
    }

    @Test func disappearanceToHiddenSnapsGeometry() {
        // hud→empty and compact→empty: the reverse path must not ghost-morph.
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: true, expanding: false, reduceMotion: false) == nil)
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: true, expanding: true, reduceMotion: false) == nil)
    }

    @Test func hiddenToHiddenSnaps() {
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: true, toEmpty: true, expanding: false, reduceMotion: false) == nil)
    }

    @Test func visibleToVisibleMorphsUnderTheDirectionalSpring() {
        // compact→expanded opens; expanded→compact and now-playing↔hud close.
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: false, expanding: true, reduceMotion: false) == SurfaceAnimation.open)
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: false, expanding: false, reduceMotion: false) == SurfaceAnimation.close)
    }

    // MARK: - Content crossfade provenance (the material/clip bounds shield)

    @Test func appearanceSnapsTheContentBounds() {
        // fromEmpty ⇒ nil: the crossfade scope also sizes the material/clip/stroke,
        // so an appearance must snap them to the destination instead of springing
        // past the snapped outer frame (the ghost behind the HUD). Direction is
        // irrelevant when appearing.
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: true, expanding: false, reduceMotion: false) == nil)
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: true, expanding: true, reduceMotion: false) == nil)
    }

    @Test func disappearanceKeepsTheFadeSpring() {
        // toEmpty (not fromEmpty) ⇒ the outgoing glyph fades with the surface
        // rather than popping; the frozen empty geometry means the spring has no
        // size delta to drag.
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: false, expanding: false, reduceMotion: false) == SurfaceAnimation.close)
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: false, expanding: true, reduceMotion: false) == SurfaceAnimation.open)
    }

    // MARK: - Reduce Motion (MG5: every morph lands dry; fades survive elsewhere)

    @Test func reduceMotionSuppressesTheGeometryMorph() {
        // The visible→visible frame/flare morph resolves to nil under the
        // preference; the opacity fade (animated separately in each view) is not
        // routed through here and so stays.
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: false, expanding: true, reduceMotion: true) == nil)
        #expect(SurfaceAnimation.geometryAnimation(fromEmpty: false, toEmpty: false, expanding: false, reduceMotion: true) == nil)
    }

    @Test func reduceMotionSuppressesTheContentMorph() {
        // The disappearance/visible crossfade spring resolves to nil under the
        // preference (an appearance was already nil by provenance).
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: false, expanding: true, reduceMotion: true) == nil)
        #expect(SurfaceAnimation.contentAnimation(fromEmpty: false, expanding: false, reduceMotion: true) == nil)
    }

    @Test func reduceMotionSuppressesThePlainMorph() {
        // The view-only resize / width-hug morph: dry under the preference, the
        // open spring otherwise.
        #expect(SurfaceAnimation.morph(reduceMotion: true) == nil)
        #expect(SurfaceAnimation.morph(reduceMotion: false) == SurfaceAnimation.open)
    }
}
