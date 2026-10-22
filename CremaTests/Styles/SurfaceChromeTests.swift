import AppKit
import SwiftUI
import Testing
@testable import Crema

/// The floating surface's edge, pinned as numbers. Every value here is
/// calibratable on hardware, so the assertions are about the SHAPE — a film that
/// darkens, a specular that falls from the top to nothing and actually paints,
/// a material kept off the antialiased outline, one home for the tiles to read —
/// never about a particular tuning. Each one exists because the opposite
/// compiles, renders and looks almost right: a film at zero leaves the surface
/// pale over a bright desktop, an inverted gradient lights the bottom edge, a
/// zeroed width draws nothing at all, a material reaching the outline puts a grey
/// fringe round a light fill, and a forked number in the Settings tile depicts an
/// edge the app does not have.
///
/// Honest about its reach: what these pin is the constants and their relations,
/// never the view sites that stroke them — deleting an overlay in
/// `vibrantSurface` or hard-coding a white 0.12 into a body leaves
/// this suite green. That is the confessed view-body class from the
/// composition-root gap (AGENTS.md), and docs/ACCEPTANCE.md item 25 (Card and
/// Classic over a white page) is what covers the wiring.
struct SurfaceChromeTests {

    @Test func theFilmDarkensTheSurfaceWithoutHidingTheMaterial() throws {
        // The film is what keeps the surface dark over a bright desktop: it must
        // be black, there, and short of opaque, or the material's blur is gone.
        #expect(SurfaceChrome.scrimOpacity > 0)
        #expect(SurfaceChrome.scrimOpacity < 1)
        let film = try #require(NSColor(SurfaceChrome.scrim).usingColorSpace(.deviceGray))
        #expect(film.whiteComponent == 0)
        #expect(abs(film.alphaComponent - SurfaceChrome.scrimOpacity) < 0.001)
    }

    @Test func theMaterialStopsShortOfTheOutline() {
        // At zero the material's antialiased edge darkens a light fill's: the
        // fringe the inset exists to keep off the filled HUD. Past a point it
        // would show as an unblurred band, so it stays under one stroke width.
        #expect(SurfaceChrome.materialInset > 0)
        #expect(SurfaceChrome.materialInset <= SurfaceChrome.specularWidth)
    }

    @Test func theSpecularRunsFromTheTopDownToNothing() throws {
        let stops = SurfaceChrome.specularStops
        #expect(stops.count >= 2)
        let first = try #require(stops.first)
        let last = try #require(stops.last)

        // Brightest at the very top, gone by the end: light comes from above,
        // and a highlight that survives to the bottom edge reads as a ring.
        #expect(SurfaceChrome.specularTopOpacity > 0)
        #expect(first.location == 0)
        #expect(first.opacity == SurfaceChrome.specularTopOpacity)
        #expect(last.opacity == 0)

        // Monotone in both axes — an out-of-order or non-decreasing pair is a
        // gradient that brightens on the way down.
        for (earlier, later) in zip(stops, stops.dropFirst()) {
            #expect(later.location >= earlier.location)
            #expect(later.opacity <= earlier.opacity)
        }

        // The stop locations only mean "top→bottom" while the axis says so;
        // flipping the endpoints would light the bottom edge with the same
        // numbers.
        #expect(SurfaceChrome.specularStart == .top)
        #expect(SurfaceChrome.specularEnd == .bottom)
    }

    @Test func theSpecularActuallyPaints() {
        // A zero line width is an invisible highlight that no other assertion
        // here can see: the color and the ramp stay perfectly correct.
        #expect(SurfaceChrome.specularWidth > 0)
    }

    @Test func theTileStrokeNeverFallsBelowTheSpecularsTopOpacity() {
        // The Settings tile draws one flat hairline where the surface draws a
        // ramp, so it takes the ramp's brightest point and may only go
        // brighter: at thumbnail scale a dimmer edge reads as no edge, and a
        // number forked from this one depicts a border the app does not draw.
        #expect(SurfaceChrome.tileStrokeTopOpacity >= SurfaceChrome.specularTopOpacity)
        #expect(SurfaceChrome.tileStrokeTopOpacity > 0)
    }

    @Test func theDimmedGlassHoldsWhiteInkInsideTheBandEveryInkIsHeldAgainst() {
        // The player's accent and text, and under Increase Contrast the filled
        // HUD's glyph and every white ink on the indicator, are held against the
        // band the film path sets; the dimmed glass, measured, must sit inside
        // it, or those tests stop speaking for it.
        #expect(SurfaceChrome.glassDimOpacity > 0)
        #expect(SurfaceChrome.glassDimOpacity < 1)
        #expect(SurfaceChrome.glassDimmedInkRatioOverWhitePage >= SurfaceChrome.whiteInkRatioOverWhitePage)
        #expect(SurfaceChrome.glassDimmedInkRatioOverBlackDesktop >= SurfaceChrome.whiteInkRatioOverBlackDesktop)
    }

    @Test func theBareGlassIsBelowTheMinimumAndSaysSo() {
        // The indicator's accepted exception: a number recorded, not a guarantee,
        // so nothing may hold ink against it as if it were one, and no text sits
        // on it.
        #expect(SurfaceChrome.glassBareInkRatioOverWhitePage < WCAGContrast.minimumRatio)
    }

    @Test func theGlassRimSpansTheBandTheCutGlassLeaves() {
        // Between the outline and the cut glass lies a band the glass does not
        // reach; a rim narrower than it shows the backdrop raw there, a dark seam
        // over a black page.
        let widest = SurfaceChrome.glassRim.map(\.width).max() ?? 0
        #expect(widest >= SurfaceChrome.glassInset + SurfaceChrome.glassEdgeCut)
    }

    @Test func theGlassRimIsLitFromAboveAndAlmostAbsentDownTheSides() {
        // Read off the system's OSD: its edge is bright along the top, second
        // along the bottom, and next to nothing midway down the sides, which is
        // what keeps it from reading as a drawn outline. The light strokes say so
        // in their ramps; none goes negative.
        for stroke in SurfaceChrome.glassRim {
            #expect(min(stroke.top, stroke.middle, stroke.bottom) >= 0)
            #expect(stroke.top >= stroke.middle)
            #expect(stroke.bottom >= stroke.middle)
        }
        let light = SurfaceChrome.glassRim.filter { $0.middle == 0 }
        #expect(!light.isEmpty)
        #expect(SurfaceChrome.glassRimHeld.from < SurfaceChrome.glassRimHeld.to)
    }

    @Test func theGlassShadowIsSoftAndFallsDown() {
        #expect(SurfaceChrome.glassShadowOpacity > 0)
        #expect(SurfaceChrome.glassShadowOpacity < 0.5)
        #expect(SurfaceChrome.glassShadowY > 0)
    }

    @Test func thePlayersGlassReachesTheOutlineAndTheIndicatorsStopsShortOfIt() {
        // Under the player's dimming a band without glass shows the page through
        // the layer, a light ring round a dark body over a pale page.
        #expect(SurfaceChrome.glassStop(carriesText: true) == (0, 0))
        #expect(SurfaceChrome.glassStop(carriesText: false)
            == (SurfaceChrome.glassInset, SurfaceChrome.glassEdgeCut))
    }

    @Test func thePlayersRimIsTheLightAloneAndSofter() {
        // No band to carry, so no band stroke; and no stroke of it brighter than
        // the indicator's, which is the one matched to the system's.
        let indicator = SurfaceChrome.glassRim(carriesText: false)
        let player = SurfaceChrome.glassRim(carriesText: true)
        #expect(indicator.map(\.width) == SurfaceChrome.glassRim.map(\.width))
        #expect(player.map(\.width) == SurfaceChrome.glassRim.dropFirst().map(\.width))
        for (soft, matched) in zip(player, SurfaceChrome.glassRim.dropFirst()) {
            #expect(soft.top < matched.top && soft.middle <= matched.middle && soft.bottom < matched.bottom)
            #expect(soft.top > 0)
        }
    }
}
