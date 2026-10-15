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
}
