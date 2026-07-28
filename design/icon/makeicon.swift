// Renders the macOS app-icon set from the square 4096 master:
// Apple's Big Sur+ template geometry — 1024 pt canvas, squircle body 824 pt
// centered (continuous-corner radius 185.4 pt), subtle drop shadow
// (black 30%, y +10, blur 10 at 1024) — everything scaled linearly per size.
// Each slot renders straight from the 4096 master (high interpolation).
//
// Optical correction at tiny POINT sizes (standard icon practice): the pill
// occupies ~64% of the master's width, which at 16 pt reads as a 2 px dash —
// so the 16 pt slots zoom the art 1.42x and the 32 pt slots 1.22x (center
// crop; the pill and its baked shadow stay fully inside the crop at both).
// Zoom follows the POINT size, not the pixel size: 16@2x (32 px) must match
// 16@1x optically, not 32@1x.
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct IconView: View {
    let master: NSImage
    let canvas: CGFloat
    let zoom: CGFloat

    var body: some View {
        let s = canvas / 1024.0
        let bodySide = 824.0 * s
        let radius = 185.4 * s
        ZStack {
            Color.clear
            Image(nsImage: master)
                .resizable()
                .interpolation(.high)
                .frame(width: bodySide * zoom, height: bodySide * zoom)
                .frame(width: bodySide, height: bodySide)
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(0.3), radius: 10 * s, x: 0, y: 10 * s)
        }
        .frame(width: canvas, height: canvas)
    }
}

MainActor.assumeIsolated {
    let args = CommandLine.arguments
    guard args.count == 3 else { fatalError("usage: makeicon <master.png> <outdir>") }
    guard let master = NSImage(contentsOf: URL(fileURLWithPath: args[1])) else {
        fatalError("cannot load master")
    }
    let outDir = URL(fileURLWithPath: args[2], isDirectory: true)
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    func zoom(forPoints points: Int) -> CGFloat {
        switch points {
        case 16: 1.42
        case 32: 1.22
        default: 1.0
        }
    }

    for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
                            (256, 1), (256, 2), (512, 1), (512, 2)] {
        let pixels = points * scale
        let renderer = ImageRenderer(content: IconView(
            master: master, canvas: CGFloat(pixels), zoom: zoom(forPoints: points)
        ))
        renderer.scale = 1.0
        guard let cg = renderer.cgImage else { fatalError("render failed at \(points)@\(scale)x") }
        precondition(cg.width == pixels && cg.height == pixels, "unexpected size \(cg.width)")
        let suffix = scale == 2 ? "@2x" : ""
        let url = outDir.appendingPathComponent("AppIcon-\(points)\(suffix).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("dest failed")
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { fatalError("write failed at \(points)@\(scale)x") }
        print("wrote \(url.lastPathComponent) (\(pixels)px, zoom \(zoom(forPoints: points)))")
    }
}
