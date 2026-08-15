import Testing
@testable import Crema

/// The accent's one animation: the fade the tone arrives with when extraction
/// lands, a beat after the surface.
///
/// It sits apart from `ArtworkAccentTests`, which is about the PICKER — which
/// pixels vote and what tone they elect. This is about motion, and it is here
/// because the tone fade was the last leaf in the app still spending an animation
/// unconditionally: the app-wide gate (MG5) is asserted per rule, one rule at a
/// time, and a leaf with no assertion of its own is exactly how one veto ends up
/// observed and another forgotten.
struct ArtworkAccentMotionTests {

    @Test func reduceMotionLandsTheToneWithoutTheFade() {
        // A colour cross-fade is not the substitution the preference asks for —
        // it is an animation on a surface that sits over the menu bar. The
        // precedent is `CapsuleTrack.knobReveal`, which answers nil and lets the
        // knob snap; nil here is `withAnimation`'s own "no animation".
        #expect(ArtworkAccent.toneFade(reduceMotion: true) == nil)
    }

    @Test func withoutThePreferenceTheToneStillFadesIn() {
        // The fade exists for a reason worth keeping: a bare snap read as a
        // flicker against the outgoing branch's ghost.
        #expect(ArtworkAccent.toneFade(reduceMotion: false) != nil)
        #expect(ArtworkAccent.toneFadeDuration > 0)
    }
}
