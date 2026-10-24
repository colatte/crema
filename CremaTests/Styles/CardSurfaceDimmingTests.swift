import SwiftUI
import Testing
@testable import Crema

/// When the Card's glass is dimmed. Under text always: the player's white text
/// must be read, and bare glass over a pale page leaves it near 1.7:1. Under the
/// indicator only with Increase Contrast: a glyph and a bar read by their shape,
/// shown bare as the system's OSD shows them, until that setting asks for the
/// minimum (docs/DECISIONS.md: the-card-is-glass).
struct CardSurfaceDimmingTests {

    @Test func thePlayerIsDimmedWhateverTheContrast() {
        #expect(SurfaceChrome.glassDimming(.standard, carriesText: true) == SurfaceChrome.glassDimOpacity)
        #expect(SurfaceChrome.glassDimming(.increased, carriesText: true) == SurfaceChrome.glassDimOpacity)
    }

    @Test func theIndicatorIsBareUntilIncreaseContrast() {
        #expect(SurfaceChrome.glassDimming(.standard, carriesText: false) == 0)
        #expect(SurfaceChrome.glassDimming(.increased, carriesText: false) == SurfaceChrome.glassDimOpacity)
    }

    @Test func everyPlayerStateCarriesTextAndTheHUDNone() {
        // Keyed on the effective layout, which resolves a fading surface to the
        // layout it is leaving, so a fading HUD arrives here as `.hud`. `.empty`
        // draws nothing; dimmed is the answer that can never leave text bare.
        for kind in [CardView.LayoutKind.compact, .expanded, .empty] {
            #expect(CardView.surfaceCarriesText(for: kind), "\(kind)")
        }
        #expect(!CardView.surfaceCarriesText(for: .hud))
    }

    @Test func onTheGlassTheFilledRemainderIsTheGlassUntilIncreaseContrast() {
        // The remainder is the glass itself by default, so the fill sweeps over a
        // surface that follows the backdrop; under Increase Contrast the dimmed
        // glass gets the film path's remainder, which the glyph's contrast test
        // holds to the minimum.
        #expect(CardMetrics.hudFilledEmptyOpacity(.standard, onGlass: true) == 0)
        #expect(CardMetrics.hudFilledEmptyOpacity(.increased, onGlass: true)
            == CardMetrics.hudFilledEmptyOpacity(.increased, onGlass: false))
    }
}
