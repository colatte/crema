import Foundation

/// The contrast arithmetic the skins' ink is held to, pure so the guarantee is a
/// test rather than a claim. The formulas are WCAG 2.2's definitions of "relative
/// luminance" and "contrast ratio" (w3.org/TR/WCAG22, sRGB transfer threshold
/// 0.04045), the standard Apple's Accessibility HIG cites for its minimums: 4.5:1
/// for text and icons up to 17 pt.
///
/// Values are sRGB-encoded components in 0…1, the space the surfaces composite in.
enum WCAGContrast {
    /// The HIG's floor for text and icons up to 17 pt — every glyph on the
    /// surfaces is under it.
    nonisolated static let minimumRatio: Double = 4.5

    /// One encoded component, linearized.
    nonisolated static func linear(_ encoded: Double) -> Double {
        encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }

    /// The inverse of `linear`: the encoded gray whose luminance is `luminance`.
    nonisolated static func encoded(luminance: Double) -> Double {
        luminance <= 0.04045 / 12.92 ? luminance * 12.92 : 1.055 * pow(luminance, 1 / 2.4) - 0.055
    }

    nonisolated static func luminance(red: Double, green: Double, blue: Double) -> Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    nonisolated static func luminance(gray: Double) -> Double {
        linear(gray)
    }

    /// The luminance of an HSB colour, by the same conversion `Color(hue:…)` draws.
    nonisolated static func luminance(hue: Double, saturation: Double, brightness: Double) -> Double {
        let rgb = rgb(hue: hue, saturation: saturation, brightness: brightness)
        return luminance(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// Lighter over darker, whichever order they come in.
    nonisolated static func ratio(_ first: Double, _ second: Double) -> Double {
        (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    /// The background a white ink measured at `whiteInkRatio` stands on.
    nonisolated static func backgroundLuminance(underWhiteInkAt whiteInkRatio: Double) -> Double {
        1.05 / whiteInkRatio - 0.05
    }

    /// The least luminance a lighter ink needs to stand `ratio` above `background`.
    nonisolated static func luminance(reaching ratio: Double, above background: Double) -> Double {
        ratio * (background + 0.05) - 0.05
    }

    nonisolated static func rgb(
        hue: Double, saturation: Double, brightness: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let chroma = brightness * saturation
        let rising = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let floor = brightness - chroma
        let (red, green, blue): (Double, Double, Double) = switch Int(sector) {
        case 0: (chroma, rising, 0)
        case 1: (rising, chroma, 0)
        case 2: (0, chroma, rising)
        case 3: (0, rising, chroma)
        case 4: (rising, 0, chroma)
        default: (chroma, 0, rising)
        }
        return (red + floor, green + floor, blue + floor)
    }
}
