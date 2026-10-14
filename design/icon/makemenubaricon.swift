// Generates the menu bar TEMPLATE icon (Crema/Assets.xcassets/MenuBarIcon.imageset)
// from the app icon's mark, the same vector (crema-mark.svg) filled solid:
// a 16 pt mark centered in the 18 pt slot. Monochrome black + alpha; the
// asset's template rendering intent lets the system tint it for
// dark/light/accent. At 18 pt the crema's fine point thins to nothing — the
// hollow as a whole is what survives, and it is enough.
// Run: swift design/icon/makemenubaricon.swift  (writes the imageset PNGs)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

// The same reader as makemaster.swift: each script runs standalone with
// `swift <file>`, so neither can import the other's.
func markPath(svg: URL) -> CGPath {
    let text = try! String(contentsOf: svg, encoding: .utf8)
    guard let open = text.range(of: " d=\""),
          let close = text[open.upperBound...].range(of: "\"") else { fatalError("no path data in \(svg.path)") }
    let tokens = text[open.upperBound..<close.lowerBound].split(whereSeparator: { $0.isWhitespace || $0 == "," })
    var index = 0
    func number() -> CGFloat {
        defer { index += 1 }
        return CGFloat(Double(tokens[index])!)
    }
    func point() -> CGPoint { CGPoint(x: number(), y: number()) }
    let path = CGMutablePath()
    while index < tokens.count {
        let command = tokens[index]
        index += 1
        switch command {
        case "M": path.move(to: point())
        case "C":
            let c1 = point(), c2 = point()
            path.addCurve(to: point(), control1: c1, control2: c2)
        case "Z": path.closeSubpath()
        default: fatalError("unsupported path command \(command)")
        }
    }
    return path
}

struct Mark: Shape {
    let source: Path

    func path(in rect: CGRect) -> Path {
        let bounds = source.cgPath.boundingBoxOfPath
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let transform = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        return source.applying(transform)
    }
}

struct MenuBarIconView: View {
    let mark: Path

    var body: some View {
        Mark(source: mark)
            .fill(Color.black)
            .frame(width: 16, height: 16)
            .frame(width: 18, height: 18)
    }
}

MainActor.assumeIsolated {
    let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    let imageset = scriptDir
        .appendingPathComponent("../../Crema/Assets.xcassets/MenuBarIcon.imageset")
        .standardizedFileURL
    try? FileManager.default.createDirectory(at: imageset, withIntermediateDirectories: true)
    let mark = Path(markPath(svg: scriptDir.appendingPathComponent("crema-mark.svg")))
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
        let renderer = ImageRenderer(content: MenuBarIconView(mark: mark))
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
