import AppKit
import SwiftUI
import Testing
@testable import Crema

/// The 2026 border, pinned as numbers. Every value here is calibratable on
/// hardware, so the assertions are about the SHAPE of the border — a rim that
/// darkens, a specular that falls from the top to nothing, two strokes that
/// actually paint, one home for the tiles to read — never about a particular
/// tuning. Each one exists because the opposite compiles, renders and looks
/// almost right: a white rim vanishes over a bright desktop, an inverted
/// gradient lights the bottom edge, a zeroed width draws nothing at all, and a
/// forked number in the Settings tile depicts a border the app does not have.
///
/// Honest about its reach: what these pin is the constants and their relations,
/// never the view sites that stroke them — deleting an overlay in
/// `vibrantSurface` or hard-coding the old white 0.12 back into a body leaves
/// this suite green. That is the confessed view-body class from the
/// composition-root gap (CLAUDE.md), and the smoke item "borda 2026 em sala
/// clara/escura" is what covers the wiring.
struct SurfaceChromeTests {

    @Test func theOuterRimDarkensInsteadOfLightening() throws {
        // The pre-2026 border was a single white hairline: it defines nothing
        // over a bright wallpaper, which is exactly where a floating surface
        // needs its boundary most. The rim must sit at the dark end.
        #expect(SurfaceChrome.outerHairlineWhite < 0.5)
        #expect(SurfaceChrome.outerHairlineOpacity > 0)
        #expect(SurfaceChrome.outerHairlineOpacity < 1)

        // Through the derived color too: the constants above only govern the
        // border if the Color the view actually strokes carries them.
        let rim = try #require(NSColor(SurfaceChrome.outerHairlineColor).usingColorSpace(.deviceGray))
        #expect(rim.whiteComponent < 0.5)
        #expect(rim.alphaComponent > 0)
        #expect(rim.alphaComponent < 1)
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

    @Test func bothStrokesActuallyPaint() {
        // A zero line width is an invisible border that no other assertion
        // here can see: the color and the ramp stay perfectly correct.
        #expect(SurfaceChrome.outerHairlineWidth > 0)
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
