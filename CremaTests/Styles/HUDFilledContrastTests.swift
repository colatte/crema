import SwiftUI
import Testing
@testable import Crema

/// The filled HUD's glyph rides at the bar's start, over the light fill at a
/// high level and over the dark remainder at a low one, so it has two
/// backgrounds and no single ink reads on both: a grey that clears one fails the
/// other (0.5 white comes out near 3:1 on each). The relation
/// pinned here is the glyph against whatever the bar draws beneath it, at the
/// two extremes the floating surface itself reaches — over a black desktop and
/// over a white page (`SurfaceChrome`) — in the encoded space the surface
/// composites in. That band is the film path's, and the Card's glass under
/// Increase Contrast, dimmed into it; the bare glass is the recorded exception
/// (docs/DECISIONS.md: the-card-is-glass).
struct HUDFilledContrastTests {

    private var surfaces: [Double] {
        [SurfaceChrome.whiteInkRatioOverBlackDesktop, SurfaceChrome.whiteInkRatioOverWhitePage].map {
            WCAGContrast.encoded(luminance: WCAGContrast.backgroundLuminance(underWhiteInkAt: $0))
        }
    }

    private func worstRatio(_ contrast: ColorSchemeContrast) -> Double {
        let fill = CardMetrics.hudFilledFillOpacity(contrast)
        let empty = CardMetrics.hudFilledEmptyOpacity(contrast, onGlass: false)
        var worst = Double.infinity
        for surface in surfaces {
            for backdrop in [fill + (1 - fill) * surface, (1 - empty) * surface] {
                let glyph = CardMetrics.hudFilledGlyph(over: backdrop)
                worst = min(worst, WCAGContrast.ratio(
                    WCAGContrast.luminance(gray: glyph), WCAGContrast.luminance(gray: backdrop)
                ))
            }
        }
        return worst
    }

    @Test func theGlyphReadsOverTheFillAndTheRemainderOnAnyDesktop() {
        #expect(worstRatio(.standard) >= WCAGContrast.minimumRatio)
    }

    @Test func increasedContrastRaisesTheGlyphFurther() {
        #expect(CardMetrics.hudFilledFillOpacity(.increased) > CardMetrics.hudFilledFillOpacity(.standard))
        #expect(CardMetrics.hudFilledEmptyOpacity(.increased, onGlass: false)
            > CardMetrics.hudFilledEmptyOpacity(.standard, onGlass: false))
        #expect(worstRatio(.increased) > worstRatio(.standard))
    }
}
