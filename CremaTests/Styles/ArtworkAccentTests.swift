import AppKit
import Testing
@testable import Crema

/// The accent picker: pure over RGBA pixels. The contract under test is the
/// Apple-restraint policy — a real tone only for genuinely colorful covers,
/// clamped into the contained display band; everything else nil (neutral).
struct ArtworkAccentTests {

    /// Builds an RGBA pixel array from repeating (r, g, b) triples.
    private func pixels(_ colors: [(UInt8, UInt8, UInt8)], count: Int) -> [UInt8] {
        var out: [UInt8] = []
        for index in 0..<count {
            let (r, g, b) = colors[index % colors.count]
            out.append(contentsOf: [r, g, b, 255])
        }
        return out
    }

    @Test func aDominantSaturatedColorWinsAndLandsInTheDisplayBand() {
        // Mostly vivid red with some gray: red must win, clamped into band.
        let tone = ArtworkAccent.tone(fromRGBA: pixels([(230, 30, 30), (230, 30, 30), (128, 128, 128)], count: 256))
        #expect(tone != nil)
        if let tone {
            #expect(tone.hue < 0.06 || tone.hue > 0.94)   // red family
            #expect(ArtworkAccent.displaySaturationRange.contains(tone.saturation))
            #expect(ArtworkAccent.displayBrightnessRange.contains(tone.displayBrightness))
        }
    }

    @Test func redsAcrossTheHueWraparoundVoteAsOneBucket() {
        // Hue 0.98 and hue 0.02 are both "red": the half-bucket rotation must
        // pool them. Calibrated so each red sub-family alone loses to teal —
        // the reds win only when pooled, which is the mechanism under test.
        let crimson: (UInt8, UInt8, UInt8) = (220, 20, 45)    // hue just below 1
        let scarlet: (UInt8, UInt8, UInt8) = (220, 45, 20)    // hue just above 0
        let teal: (UInt8, UInt8, UInt8) = (20, 160, 160)
        let tone = ArtworkAccent.tone(fromRGBA: pixels([crimson, scarlet, teal, teal], count: 248))
        #expect(tone != nil)
        if let tone {
            #expect(tone.hue < 0.08 || tone.hue > 0.92)
        }
    }

    @Test func monochromeCoversGetNoTone() {
        // Grayscale and near-black covers: nothing colorful enough to vote.
        #expect(ArtworkAccent.tone(fromRGBA: pixels([(128, 128, 128), (30, 30, 30), (220, 220, 220)], count: 256)) == nil)
        #expect(ArtworkAccent.tone(fromRGBA: pixels([(5, 5, 8)], count: 256)) == nil)
    }

    @Test func aFewColorfulPixelsInAGrayCoverAreNotEnough() {
        // Below the colorful-mass floor: one vivid pixel in 64 must not tint
        // the whole surface.
        var quads = [(UInt8, UInt8, UInt8)](repeating: (100, 100, 100), count: 63)
        quads.append((255, 0, 0))
        #expect(ArtworkAccent.tone(fromRGBA: pixels(quads, count: 64)) == nil)
    }

    @Test func theColorfulMassFloorIsInclusive() {
        // Exactly at the 8% floor (8 of 100) qualifies; one voter short does
        // not — pins the >= boundary.
        func cover(colorful: Int) -> [UInt8] {
            let red: (UInt8, UInt8, UInt8) = (255, 0, 0)
            var quads = [(UInt8, UInt8, UInt8)](repeating: (100, 100, 100), count: 100 - colorful)
            quads.append(contentsOf: [(UInt8, UInt8, UInt8)](repeating: red, count: colorful))
            return pixels(quads, count: 100)
        }
        #expect(ArtworkAccent.tone(fromRGBA: cover(colorful: 8)) != nil)
        #expect(ArtworkAccent.tone(fromRGBA: cover(colorful: 7)) == nil)
    }

    @Test func neonCoversAreContainedByTheClamp() {
        // Full-saturation full-brightness green: the tone must come out
        // capped into the single display band, never the raw neon.
        let tone = ArtworkAccent.tone(fromRGBA: pixels([(0, 255, 0)], count: 256))
        #expect(tone?.saturation == ArtworkAccent.displaySaturationRange.upperBound)
        #expect(tone?.displayBrightness == ArtworkAccent.displayBrightnessRange.upperBound)
    }

    @Test func darkButColorfulCoversAreLiftedToTheFloor() {
        // A deep blue (visible hue, low brightness): lifted to the band's
        // floor so it reads on the always-dark surfaces (docs/DECISIONS.md:
        // hud-fixed-dark-palette).
        let tone = ArtworkAccent.tone(fromRGBA: pixels([(20, 30, 90)], count: 256))
        #expect(tone != nil)
        #expect(tone?.displayBrightness == ArtworkAccent.displayBrightnessRange.lowerBound)
    }

    @Test func emptyPixelsGetNoTone() {
        #expect(ArtworkAccent.tone(fromRGBA: []) == nil)
    }

    @Test func extractionFallsBackToNilOnMissingOrUndecodableBytes() {
        #expect(ArtworkAccent.extract(from: nil) == nil)
        #expect(ArtworkAccent.extract(from: [0x00, 0x01, 0x02, 0x03]) == nil)
    }

    @Test func extractionReadsARealEncodedImage() throws {
        // End-to-end through the border: an encoded PNG of a solid vivid
        // orange must come back as an orange-family tone.
        let image = NSImage(size: NSSize(width: 32, height: 32))
        image.lockFocus()
        NSColor(red: 0.95, green: 0.55, blue: 0.1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        image.unlockFocus()
        let png = try #require(
            image.tiffRepresentation
                .flatMap { NSBitmapImageRep(data: $0) }
                .flatMap { $0.representation(using: .png, properties: [:]) }
        )

        let tone = ArtworkAccent.extract(from: Array(png))

        #expect(tone != nil)
        if let tone {
            #expect(tone.hue > 0.02 && tone.hue < 0.18)   // orange family
        }
    }

    @Test func hsbConversionMatchesKnownAnchors() {
        let red = ArtworkAccent.hsb(red: 1, green: 0, blue: 0)
        #expect(red.hue == 0 && red.saturation == 1 && red.brightness == 1)
        let green = ArtworkAccent.hsb(red: 0, green: 1, blue: 0)
        #expect(abs(green.hue - 1.0 / 3.0) < 0.001)
        let gray = ArtworkAccent.hsb(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.saturation == 0)
    }
}
