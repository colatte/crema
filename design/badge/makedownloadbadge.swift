// Generates the README's download button (docs/assets/download-macos.png).
// Anatomy is the App Store lineage every Mac app uses: near-black rounded plate,
// hairline border, Apple mark at the left, "Download app for" over "macOS". The
// one liberty is warmth — the ground is not neutral black but the app icon's
// roasted coffee pushed almost to black (#0C0A08, sampled from the icon art),
// and the hairline carries the icon's crema instead of cold white. Sober on the
// surface, warm underneath; still reads as black beside GitHub's chrome, and the
// hairline is what separates the plate from a dark page (on a light one the
// plate separates itself).
// Rendered at 2x and displayed at its point width in the README, so it stays
// crisp on Retina. Regenerate here, never edit the PNG by hand.
// Run: swift design/badge/makedownloadbadge.swift
// To eyeball a change before shipping it, wrap BadgeView in
// `.padding(40).background(Color.white)` (and the GitHub dark #0d1117) and write
// those to a scratch path — the calibration that produced the nudges below.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum Metrics {
    static let corner: CGFloat = 15
    // Leading is a hair tighter than trailing: the Apple mark is an all-curve
    // silhouette and needs the extra overhang to sit level with the flat right edge.
    static let padLeading: CGFloat = 24
    static let padTrailing: CGFloat = 26
    static let vPadding: CGFloat = 12.75
    // The plate is sized by SwiftUI's line boxes, which reserve descender slack
    // under a "macOS" that has none — centering on them leaves the ink riding
    // high. This drops the lockup so the block's cap-to-baseline mass sits on the
    // plate's center instead. Applied as an offset, not padding, so it moves the
    // content without resizing the plate. Both nudges are measured, not guessed
    // (measure.swift reports the residual); re-derive them if a font size changes.
    static let contentNudge: CGFloat = 1.6
    // The gap from the Apple mark to the text stays clearly under the side
    // padding, so the eye groups the mark WITH the text instead of reading two
    // separate objects sitting on one plate.
    static let gap: CGFloat = 11
    static let logoSize: CGFloat = 34
    // The Apple mark lands a hair above center on purpose: the leaf inflates the
    // glyph box upward while carrying almost no visual weight, so a box-centered
    // mark reads low.
    static let logoNudge: CGFloat = -1.9
    static let capSize: CGFloat = 13.5    // "Download app for"
    static let titleSize: CGFloat = 28    // "macOS"
    static let lineGap: CGFloat = -1
    static let border: CGFloat = 1
}

private enum Palette {
    // icon.png's coffee (#281208) taken down to a near-black ground: reads black
    // next to GitHub's chrome, but the warm bias survives on a calibrated screen.
    // Calibrated against BOTH canvases, not just white: at #0C0A08 the plate was
    // DARKER than GitHub's dark page (#0d1117) and read as a hole punched through
    // it, with a 1 px hairline as the only thing describing a button — the first
    // matte screen would have lost the shape. #16130F sits just above that canvas,
    // so on dark the plate is an object resting on the page, while on white it is
    // still an undifferentiated black block (verified side by side; the three
    // candidates were indistinguishable there). Never take this below the canvas.
    static let ground = Color(red: 0x16 / 255, green: 0x13 / 255, blue: 0x0F / 255)
    // The icon's crema (#FBE7C7), not white: at 22% over the ground the hairline
    // lands warm-neutral instead of blue-cold. Same reason the ink is off-white.
    static let hairline = Color(red: 0xFB / 255, green: 0xE7 / 255, blue: 0xC7 / 255)
    static let ink = Color(red: 1.0, green: 0.995, blue: 0.985)
}

struct BadgeView: View {
    var body: some View {
        HStack(spacing: Metrics.gap) {
            Image(systemName: "apple.logo")
                .font(.system(size: Metrics.logoSize))
                .offset(y: Metrics.logoNudge)

            VStack(alignment: .leading, spacing: Metrics.lineGap) {
                Text("Download app for")
                    .font(.system(size: Metrics.capSize, weight: .medium))
                    .tracking(0.2)
                    .opacity(0.92)
                Text("macOS")
                    .font(.system(size: Metrics.titleSize, weight: .semibold))
                    .tracking(-0.2)
            }
            .fixedSize()
        }
        .foregroundStyle(Palette.ink)
        .offset(y: Metrics.contentNudge)
        .padding(.leading, Metrics.padLeading)
        .padding(.trailing, Metrics.padTrailing)
        .padding(.vertical, Metrics.vPadding)
        .background(
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .fill(Palette.ground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.corner, style: .continuous)
                .strokeBorder(Palette.hairline.opacity(0.25), lineWidth: Metrics.border)
        )
    }
}

MainActor.assumeIsolated {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let dir = scriptDir.appendingPathComponent("../../docs/assets").standardizedFileURL

    @MainActor func write(_ view: some View, to name: String, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { fatalError("render failed: \(name)") }
        let url = dir.appendingPathComponent(name)
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ) else { fatalError("destination failed: \(name)") }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("write failed: \(name)") }
        print("wrote \(url.path)  \(cg.width)x\(cg.height) px  = \(CGFloat(cg.width) / scale)x\(CGFloat(cg.height) / scale) pt")
    }

    write(BadgeView(), to: "download-macos.png")
}
