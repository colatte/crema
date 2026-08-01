import CoreGraphics
import Testing
@testable import Crema

/// The preview is only worth drawing if it says the true thing about each skin:
/// where the surface lands. These pin the properties a person reads off the
/// picture — top vs bottom, hugging the slit vs floating — so a change to a frame
/// rule that moves a surface also moves its thumbnail, or fails here.
struct StylePreviewTests {

    /// A panel with no slit: the whole class of Macs the notch skin cannot be
    /// drawn on (mini, Studio, iMac, older Air), and every external monitor.
    private let slitless = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1920, height: 1200))
    /// An ultrawide sitting to the right of a primary display. Its shape matches
    /// none of the constants in the preview, and its origin is not zero, so a rule
    /// that assumed either one shows up here instead of on someone's desk.
    private let ultrawide = ScreenGeometry(frame: CGRect(x: 1512, y: 0, width: 3440, height: 1440))

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

    // The tests above ask about the canonical panel — the default argument, and
    // what the picker calls. The ones below name a display: the same question with
    // the answer no longer fixed to one Mac.

    @Test func onASlitlessPanelTheNotchTileDrawsWhatThatDisplayWouldDraw() {
        // A tile is a picture OF a display, so on a display with no slit the notch
        // tile has to show what that display would really draw — the card — rather
        // than promise hardware the Mac does not have. It resolves through the one
        // declared→drawn mapping every reader shares, so the picture and the panel
        // cannot disagree (docs/DECISIONS.md: rendered-style-gates-settings).
        let notch = StylePreview.shapes(for: .notch, on: slitless)
        let card = StylePreview.shapes(for: .card, on: slitless)
        #expect(notch.slit == nil, "no slit is drawn for hardware that has none")
        #expect(notch.surface == card.surface, "the surface is the card's: \(notch.surface) vs \(card.surface)")
        #expect(!notch.surfaceIsOpaque, "the card's translucent material, not the notch's black camouflage")
        #expect(notch == card, "on a slitless panel the two tiles are one picture")
    }

    @Test func theMenuBarStripSurvivesADisplayWithNoSafeArea() {
        // The strip is what makes the tile read as a SCREEN, and it derives from
        // the safe area — which a slitless panel reports as zero. Derived alone the
        // picture loses its top edge on exactly the displays where every skin is a
        // floating one, and the surfaces would have nothing to float under.
        let bar = StylePreview.shapes(for: .card, on: slitless).menuBar
        #expect(bar > 0, "a tile with no top edge is not a picture of a screen")
        // The 24 pt is written out here rather than read back from production: a
        // measured number that changes has to be re-measured, not just re-run.
        #expect(abs(bar * slitless.frame.height - 24) < 0.0001, "the slitless bar measures 24 pt: \(bar)")
    }

    @Test func theTileIsShapedLikeTheDisplayItDescribes() {
        // A picture of a 21:9 monitor drawn in a 3:2 frame is a picture of some
        // other Mac, and the surface positions it illustrates land in the wrong
        // place along with it.
        let sixteenTen = StylePreview.shapes(for: .card, on: slitless).aspectRatio
        #expect(abs(sixteenTen - 1.6) < 0.0001, "1920x1200 is 16:10: \(sixteenTen)")
        let wide = StylePreview.shapes(for: .card, on: ultrawide).aspectRatio
        #expect(abs(wide - 3440.0 / 1440.0) < 0.0001, "3440x1440 is 21:9: \(wide)")
        let reference = StylePreview.shapes(for: .notch).aspectRatio
        #expect(abs(reference - 1512.0 / 982.0) < 0.0001, "the reference panel keeps its own shape: \(reference)")
    }

    @Test func everyStyleStaysInsideEveryScreen() {
        // The same guard rail as the default-panel test above, across the shapes of
        // screen the preview can be asked about: a rule that anchors off a constant
        // instead of the geometry it was handed draws off one of them.
        let screens: [(name: String, geometry: ScreenGeometry)] = [
            ("notched", StylePreview.notchedReference),
            ("slitless", slitless),
            ("ultrawide", ultrawide),
        ]
        for screen in screens {
            for style in Style.allCases {
                let surface = StylePreview.shapes(for: style, on: screen.geometry).surface
                #expect(surface.minX >= 0 && surface.maxX <= 1, "\(style) leaves \(screen.name) sideways: \(surface)")
                #expect(surface.minY >= 0 && surface.maxY <= 1, "\(style) leaves \(screen.name) vertically: \(surface)")
                #expect(surface.width > 0 && surface.height > 0, "\(style) draws nothing on \(screen.name)")
            }
        }
    }
}
