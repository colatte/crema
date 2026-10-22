import SwiftUI
import Testing
@testable import Crema

/// When the Card's glass is dimmed. By default never: the Card shows the glass
/// bare, as the system's OSD does, and accepts the system's legibility over a
/// pale page. Under Increase Contrast always, because the HIG asks that setting
/// to deliver the minimum where the default does not, and the dimmed glass is
/// measured to (docs/DECISIONS.md: the-card-is-glass).
struct CardSurfaceDimmingTests {

    @Test func theGlassIsBareByDefault() {
        #expect(SurfaceChrome.glassDimming(.standard) == 0)
    }

    @Test func increaseContrastDimsTheGlassToTheMeasuredLayer() {
        #expect(SurfaceChrome.glassDimming(.increased) == SurfaceChrome.glassDimOpacity)
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
