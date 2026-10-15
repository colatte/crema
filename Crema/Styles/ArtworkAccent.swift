import AppKit
import SwiftUI

/// Accent tone derived from the album cover — the Apple restraint model: one
/// contained tone on a single highlight element, the waveform bars, and
/// everything else neutral. The scrubber is deliberately NOT a consumer: the bar
/// is a control, and a control reads white (docs/DECISIONS.md:
/// hud-capsule-track). Extraction is pure over downsampled pixels so the picking
/// policy is unit-testable; nil means "no usable tone" and the one consumer falls
/// back to its neutral style.
enum ArtworkAccent {
    /// The picked tone: hue and saturation already clamped; brightness is kept
    /// raw and resolved into the single display band. One band suffices because
    /// every skin surface pins dark in every state and appearance
    /// (docs/DECISIONS.md: hud-fixed-dark-palette); what the band does not
    /// promise, legibility on that dark, `displayComponents` adds on top.
    struct Tone: Equatable, Sendable {
        var hue: Double
        var saturation: Double
        var rawBrightness: Double

        var displayBrightness: Double {
            min(
                max(rawBrightness, ArtworkAccent.displayBrightnessRange.lowerBound),
                ArtworkAccent.displayBrightnessRange.upperBound
            )
        }

        func color(contrast: ColorSchemeContrast) -> Color {
            let shown = displayComponents(contrast: contrast)
            return Color(hue: hue, saturation: shown.saturation, brightness: shown.brightness)
        }

        /// The colour drawn: the band's, lifted only as far as the HIG's minimum
        /// on `legibilityBackground` needs. Brightness rises first, which keeps
        /// the saturation; a hue still short at full brightness (blue, whose
        /// luminance is mostly its dimmest channel) gives saturation up toward
        /// white. Luminance rises monotonically along both moves, so a bisection
        /// finds the least change.
        func displayComponents(contrast: ColorSchemeContrast) -> (saturation: Double, brightness: Double) {
            let floor = WCAGContrast.luminance(
                reaching: WCAGContrast.minimumRatio,
                above: ArtworkAccent.legibilityBackground(contrast)
            )
            let reads = { (saturation: Double, brightness: Double) in
                WCAGContrast.luminance(hue: hue, saturation: saturation, brightness: brightness) >= floor
            }
            if reads(saturation, displayBrightness) {
                return (saturation, displayBrightness)
            }
            if reads(saturation, 1) {
                return (saturation, ArtworkAccent.nearestPassing(from: displayBrightness, to: 1) { reads(saturation, $0) })
            }
            return (ArtworkAccent.nearestPassing(from: saturation, to: 0) { reads($0, 1) }, 1)
        }
    }

    /// The background the tone has to read on. By default the darkest surface:
    /// the Notch's black and the floating surface over a dark desktop, within a
    /// hair of each other. Under Increase Contrast the floating surface at its
    /// lightest, over a white page, where the film guarantees white ink and
    /// nothing darker — the HIG asks that setting to deliver the minimum where the
    /// default does not, and over a bright desktop the default does not
    /// (docs/DECISIONS.md: ink-meets-the-minimum).
    static func legibilityBackground(_ contrast: ColorSchemeContrast) -> Double {
        WCAGContrast.backgroundLuminance(
            underWhiteInkAt: contrast == .increased
                ? SurfaceChrome.whiteInkRatioOverWhitePage
                : SurfaceChrome.whiteInkRatioOverBlackDesktop
        )
    }

    /// The value nearest `start` that `passes`, given a `start` that fails, an
    /// `end` that passes and a single crossing between them.
    private static func nearestPassing(from start: Double, to end: Double, passes: (Double) -> Bool) -> Double {
        var failing = start
        var passing = end
        for _ in 0..<32 {
            let middle = (failing + passing) / 2
            if passes(middle) {
                passing = middle
            } else {
                failing = middle
            }
        }
        return passing
    }

    // Calibration. The band is the tone's character, not its legibility:
    // saturation capped so the tone suggests rather than shouts, brightness held
    // off both ends. Alone it promised nothing — a saturated blue at its floor
    // drew 2.1:1 on the Notch's black — so `displayComponents` lifts what falls
    // short.
    static let sampleSide = 16
    /// A pixel must be at least this colorful to vote — grays and whites
    /// abstain (white is bright but has no saturation, so the floor below
    /// suffices; a saturated full-brightness pixel is a legitimate voter).
    static let minVoterSaturation: Double = 0.15
    /// Near-black pixels carry no usable hue.
    static let minVoterBrightness: Double = 0.15
    /// At least this fraction of samples must be colorful, or the cover is
    /// effectively monochrome and gets no tone (B&W covers stay neutral).
    static let minColorfulFraction: Double = 0.08
    static let displaySaturationRange: ClosedRange<Double> = 0.35...0.65
    static let displayBrightnessRange: ClosedRange<Double> = 0.6...0.85
    /// 12 hue buckets, rotated half a bucket so red (the wraparound hue)
    /// lands centered in one bucket instead of split across two.
    static let hueBuckets = 12
    /// The tint fades in when extraction lands (mid-crossfade, a beat after
    /// the surface) — a bare snap read as a flicker against the ghost.
    static let toneFadeDuration: Double = 0.25

    /// Under Reduce Motion the tone arrives without the fade (MG5): a tint sliding
    /// in on a surface that sits over the menu bar is motion like any other. The
    /// substitution is `SurfaceAnimation.respecting`'s; the fade's timing is this
    /// component's.
    static func toneFade(reduceMotion: Bool) -> Animation? {
        SurfaceAnimation.respecting(reduceMotion: reduceMotion, .easeInOut(duration: toneFadeDuration))
    }

    /// Full pipeline from raw artwork bytes: bounded decode (the same ImageIO
    /// thumbnail path `artworkImage(from:)` uses), downsample, pick. Nil anywhere
    /// (no bytes, undecodable, monochrome) means neutral.
    static func extract(from data: [UInt8]?) -> Tone? {
        guard let image = ArtworkDecoding.thumbnail(from: data, maxSide: sampleSide) else {
            return nil
        }
        return extract(from: image)
    }

    /// The same pipeline from a cover already decoded — the step the byte
    /// overload above delegates to. `rgbaPixels` redraws into a `sampleSide`
    /// box either way, so a 1024 px source gives the same answer as a freshly
    /// thumbnailed one.
    private static func extract(from image: CGImage) -> Tone? {
        guard let pixels = rgbaPixels(from: image, side: sampleSide) else { return nil }
        return tone(fromRGBA: pixels)
    }

    /// Pure picker over RGBA quads: colorful pixels vote into hue buckets,
    /// weighted by saturation × brightness (a vivid pixel says more about the
    /// cover's identity than a dull one); the winning bucket's weighted mean
    /// becomes the tone, clamped into the display band.
    static func tone(fromRGBA pixels: [UInt8]) -> Tone? {
        let pixelCount = pixels.count / 4
        guard pixelCount > 0 else { return nil }

        var bucketWeight = [Double](repeating: 0, count: hueBuckets)
        var bucketHue = [Double](repeating: 0, count: hueBuckets)
        var bucketSaturation = [Double](repeating: 0, count: hueBuckets)
        var bucketBrightness = [Double](repeating: 0, count: hueBuckets)
        var colorfulCount = 0

        for pixel in 0..<pixelCount {
            let offset = pixel * 4
            let (hue, saturation, brightness) = hsb(
                red: Double(pixels[offset]) / 255,
                green: Double(pixels[offset + 1]) / 255,
                blue: Double(pixels[offset + 2]) / 255
            )
            guard saturation >= minVoterSaturation,
                  brightness >= minVoterBrightness else { continue }
            colorfulCount += 1

            let shifted = (hue + 0.5 / Double(hueBuckets)).truncatingRemainder(dividingBy: 1)
            let bucket = min(Int(shifted * Double(hueBuckets)), hueBuckets - 1)
            let weight = saturation * brightness
            bucketWeight[bucket] += weight
            // Accumulate the shifted hue so the wraparound bucket averages
            // continuously; unshift when reading the winner out.
            bucketHue[bucket] += shifted * weight
            bucketSaturation[bucket] += saturation * weight
            bucketBrightness[bucket] += brightness * weight
        }

        guard Double(colorfulCount) / Double(pixelCount) >= minColorfulFraction,
              let winner = bucketWeight.indices.max(by: { bucketWeight[$0] < bucketWeight[$1] }),
              bucketWeight[winner] > 0 else {
            return nil
        }

        let weight = bucketWeight[winner]
        var hue = bucketHue[winner] / weight - 0.5 / Double(hueBuckets)
        if hue < 0 { hue += 1 }
        return Tone(
            hue: hue,
            saturation: (bucketSaturation[winner] / weight).clamped(to: displaySaturationRange),
            rawBrightness: bucketBrightness[winner] / weight
        )
    }

    /// Border: the cover drawn into a tiny RGBA grid — all the pixels the
    /// picker ever sees, so extraction cost is independent of cover size.
    private static func rgbaPixels(from cgImage: CGImage, side: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    /// Pure RGB→HSB (the NSColor route would drag color-space conversions
    /// into the pure picker).
    static func hsb(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, brightness: Double) {
        let maxComponent = max(red, green, blue)
        let delta = maxComponent - min(red, green, blue)
        guard maxComponent > 0, delta > 0 else { return (0, 0, maxComponent) }

        let hue: Double
        if maxComponent == red {
            hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) / 6
        } else if maxComponent == green {
            hue = ((blue - red) / delta + 2) / 6
        } else {
            hue = ((red - green) / delta + 4) / 6
        }
        return (hue < 0 ? hue + 1 : hue, delta / maxComponent, maxComponent)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private struct ArtworkAccentKey: EnvironmentKey {
    static let defaultValue: ArtworkAccent.Tone? = nil
}

extension EnvironmentValues {
    /// The cover's accent tone; nil (no cover, monochrome cover) means every
    /// consumer keeps its neutral style. Carried as the tone, not a resolved
    /// color: the consumer resolves it against the contrast setting it reads
    /// (`Tone.color(contrast:)`); the colour scheme is dark on every skin.
    var artworkAccent: ArtworkAccent.Tone? {
        get { self[ArtworkAccentKey.self] }
        set { self[ArtworkAccentKey.self] = newValue }
    }
}

extension View {
    /// Derives the accent from the artwork bytes and injects it for the one
    /// component that tints with it below (`WaveformGlyph`). Applied above
    /// the crossfading branches (one instance per skin view), so the state
    /// survives compact↔expanded and extraction truly runs once per cover —
    /// keyed on the bytes, which position ticks never change — and off the
    /// concurrency pools entirely (`blockingCall`, as `artworkImage(from:)`).
    func artworkAccent(from data: [UInt8]?) -> some View {
        modifier(ArtworkAccentModifier(data: data))
    }
}

private struct ArtworkAccentModifier: ViewModifier {
    let data: [UInt8]?
    @State private var accent: ArtworkAccent.Tone?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.artworkAccent, accent)
            .task(id: data) { [data] in
                // Extraction opens with the same blocking ImageIO thumbnail call
                // `artworkImage(from:)` makes, so it takes the same exit: off the
                // concurrency pools rather than into a detached task, which would
                // hold one of the pool's fixed threads (see `blockingCall`).
                let tone = await blockingCall {
                    ArtworkAccent.extract(from: data)
                }
                // A cancelled task means the bytes changed mid-extraction — the
                // hopped-off work isn't cancelled with it (ImageIO never checks),
                // and a slow old cover would land its tone over the successor's.
                guard !Task.isCancelled else { return }
                withAnimation(ArtworkAccent.toneFade(reduceMotion: reduceMotion)) {
                    accent = tone
                }
            }
    }
}
