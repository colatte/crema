import CoreGraphics
import Testing
@testable import Crema

/// The preview is only worth drawing if it says the true thing about each skin:
/// where the surface lands. These pin the properties a person reads off the
/// picture — top vs bottom, hugging the slit vs floating — so a change to a frame
/// rule that moves a surface also moves its thumbnail, or fails here.
struct StylePreviewTests {

    @Test func everyStylePutsItsSurfaceInsideTheScreen() {
        for style in Style.allCases {
            let surface = StylePreview.shapes(for: style).surface
            #expect(surface.minX >= 0 && surface.maxX <= 1, "\(style) leaves the screen horizontally: \(surface)")
            #expect(surface.minY >= 0 && surface.maxY <= 1, "\(style) leaves the screen vertically: \(surface)")
            #expect(surface.width > 0 && surface.height > 0, "\(style) has no surface to draw: \(surface)")
        }
    }

    @Test func onlyTheNotchPreviewDrawsASlit() {
        #expect(StylePreview.shapes(for: .notch).slit != nil)
        #expect(StylePreview.shapes(for: .card).slit == nil)
        #expect(StylePreview.shapes(for: .classic).slit == nil)
    }

    @Test func theSlitSitsAtTheTopCentreWhereTheHardwarePutsIt() {
        let slit = StylePreview.shapes(for: .notch).slit
        #expect(slit != nil)
        guard let slit else { return }
        #expect(slit.minY == 0, "the slit is cut out of the top edge, not floating below it")
        // Centred within a pixel of the measured panel's own asymmetry (663 left,
        // 664 right), which is the hardware's, not ours to round away.
        #expect(abs((slit.minX + slit.maxX) / 2 - 0.5) < 0.002)
    }

    @Test func theNotchSurfaceHangsFromTheTopEdge() {
        // What makes the notch skin recognizable: it comes down out of the top of
        // the screen rather than floating under it.
        let surface = StylePreview.shapes(for: .notch).surface
        #expect(surface.minY == 0)
    }

    @Test func theClassicSurfaceSitsLowAndTheFloatingOnesSitHigh() {
        // The one property a person actually picks on. Compared against each
        // other rather than against a magic constant, so a rule that nudges every
        // surface a few points does not fail this for no reason.
        let classic = StylePreview.shapes(for: .classic).surface
        let card = StylePreview.shapes(for: .card).surface
        let notch = StylePreview.shapes(for: .notch).surface
        #expect(classic.midY > 0.5, "classic belongs in the bottom half: \(classic)")
        #expect(card.midY < 0.5, "card belongs in the top half: \(card)")
        // Compared by their TOP edges, not their middles: the open notch surface is
        // the taller of the two, so its centre sits below the card's while its edge
        // is still the one welded to the top of the screen. Comparing midpoints
        // asserted the opposite of the truth and passed only while both were shut.
        #expect(card.minY > notch.minY, "the card floats below the edge the notch hangs from")
    }

    @Test func onlyTheNotchTileDrawsASlitAndOnlyItsSurfaceIsOpaque() {
        // All three are illustrated on the SAME panel now, because the card's rule
        // reads the safe area and a slitless reference reports zero for it — drawn
        // there the card lands 8 pt down, under the menu bar, and the picture said
        // it was welded to the bezel. What still belongs to the notch alone is the
        // slit (drawing one under Card would promise hardware that style ignores)
        // and the opaque fill: only the notch is black, because it camouflages with
        // the cutout it covers.
        #expect(StylePreview.shapes(for: .notch).slit != nil)
        #expect(StylePreview.shapes(for: .card).slit == nil)
        #expect(StylePreview.shapes(for: .classic).slit == nil)
        #expect(StylePreview.shapes(for: .notch).surfaceIsOpaque)
        #expect(!StylePreview.shapes(for: .card).surfaceIsOpaque)
        #expect(!StylePreview.shapes(for: .classic).surfaceIsOpaque)
    }

    @Test func onlyTheSkinsThatReallyClearTheBarAreDrawnClearingIt() {
        // The one exaggeration in the picture, and it is licensed by an ordering
        // that is true: on the hardware this app was built for the card anchors
        // 40 pt down against a 37 pt menu bar, so it really does clear it — by 3 pt
        // on a 982 pt screen, which is a fifth of a point once scaled into the tile.
        // Drawn faithfully its edge lands on the bar's and it reads as welded, which
        // is what the field reported twice. The notch hangs FROM that edge and must
        // never be pushed off it.
        #expect(StylePreview.shapes(for: .card).surfaceClearsTheMenuBar)
        #expect(StylePreview.shapes(for: .classic).surfaceClearsTheMenuBar)
        #expect(!StylePreview.shapes(for: .notch).surfaceClearsTheMenuBar)
    }

    @Test func theUnitConversionFlipsTheAxisRatherThanCopyingIt() {
        // AppKit measures y UP from the bottom; the preview draws y DOWN from the
        // top. A copy instead of a flip puts the classic surface on the ceiling,
        // and the picture would be wrong in the one way nobody checks twice.
        let classic = StylePreview.shapes(for: .classic).surface
        let raw = Style.classic.frame(
            for: .nowPlaying(NowPlaying(title: "", isPlaying: true, position: 0), expanded: true),
            on: StylePreview.notchedReference
        )
        let screen = StylePreview.notchedReference.frame
        #expect(abs(classic.minY - (screen.maxY - raw.maxY) / screen.height) < 0.0001)
        #expect(classic.minY > 0.5, "the classic surface is near the BOTTOM once flipped")
    }
}
