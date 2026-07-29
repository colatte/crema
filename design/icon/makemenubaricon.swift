// Generates the menu bar TEMPLATE icon (Crema/Assets.xcassets/MenuBarIcon.imageset)
// from the app icon's identity: the pill silhouette (capsule outline, the
// master's ~2:1 proportions) with the crema line — the wave-bounded lower
// fill (~54% height at the left falling to ~35% at the right, the master's
// S-flow). Monochrome black + alpha; the asset's template rendering intent
// lets the system tint it for dark/light/accent. The internal wave GRADIENT
// does not survive 18 pt — the wave as a fill boundary is what does.
// Run: swift design/icon/makemenubaricon.swift  (writes the imageset PNGs)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WaveFill: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.54))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.35),
            control1: CGPoint(x: rect.minX + rect.width * 0.42, y: rect.minY + rect.height * 0.72),
            control2: CGPoint(x: rect.minX + rect.width * 0.62, y: rect.minY + rect.height * 0.18)
        )
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct MenuBarIconView: View {
    var body: some View {
        ZStack {
            Color.clear
            ZStack {
                // Inset a hair past the 1.5 stroke: not a visible gap (none
                // survives these scales) — it keeps the fill from bleeding
                // into the stroke's antialiasing at 1x, where the two would
                // otherwise smudge into one blob.
                WaveFill()
                    .fill(Color.black)
                    .clipShape(Capsule().inset(by: 1.75))
                Capsule().strokeBorder(Color.black, lineWidth: 1.5)
            }
            .frame(width: 16, height: 8)
        }
        .frame(width: 18, height: 18)
    }
}

MainActor.assumeIsolated {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let imageset = scriptDir
        .appendingPathComponent("../../Crema/Assets.xcassets/MenuBarIcon.imageset")
        .standardizedFileURL
    try? FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
    // The Contents.json travels WITH the PNGs: the template-rendering-intent
    // it declares is what makes the system tint the icon (without it the bar
    // shows an untinted black blob in dark mode) — the script owns the whole
    // imageset so "regenerate here" is literally true.
    let contents = """
    {
      "images" : [
        {
          "filename" : "menubar-icon.png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "menubar-icon@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      },
      "properties" : {
        "template-rendering-intent" : "template"
      }
    }
    """
    try! contents.write(to: imageset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    for scale in [1, 2] {
        let renderer = ImageRenderer(content: MenuBarIconView())
        renderer.scale = CGFloat(scale)
        guard let cg = renderer.cgImage else { fatalError("render failed at \(scale)x") }
        let suffix = scale == 2 ? "@2x" : ""
        let url = imageset.appendingPathComponent("menubar-icon\(suffix).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("destination failed")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("write failed at \(scale)x") }
        print("wrote \(url.path)")
    }
}
