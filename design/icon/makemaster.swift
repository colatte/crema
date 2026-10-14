// Renders the square 4096 icon master from the vector mark (crema-mark.svg):
// the espresso ground full-bleed, edge to edge, no corners and no shadow —
// makeicon.swift applies the macOS squircle and shadow, so a master that
// carried its own would come out with both twice. The mark is crema on that
// ground, its tight bounds at 56% of the canvas width, centered.
// Colours are the landing's tokens (docs/index.html): the ground is --raise
// #1b1610 and the mark --cream #d6bd94, so the icon and the page share one
// palette.
// Run: swift design/icon/makemaster.swift  (writes crema-master-4096.png)
import AppKit
import UniformTypeIdentifiers

let side = 4096
let markShare: CGFloat = 0.56

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

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let path = markPath(svg: scriptDir.appendingPathComponent("crema-mark.svg"))
let bounds = path.boundingBoxOfPath
let scale = CGFloat(side) * markShare / bounds.width
// SVG is y-down, CoreGraphics y-up: flip while centering the tight bounds.
var transform = CGAffineTransform(translationX: CGFloat(side) / 2, y: CGFloat(side) / 2)
    .scaledBy(x: scale, y: -scale)
    .translatedBy(x: -bounds.midX, y: -bounds.midY)
guard let placed = path.copy(using: &transform),
      let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("context failed") }
ctx.setFillColor(CGColor(srgbRed: 0x1B / 255, green: 0x16 / 255, blue: 0x10 / 255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
ctx.addPath(placed)
ctx.setFillColor(CGColor(srgbRed: 0xD6 / 255, green: 0xBD / 255, blue: 0x94 / 255, alpha: 1))
ctx.fillPath()

let url = scriptDir.appendingPathComponent("crema-master-4096.png")
guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("destination failed") }
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write failed") }
print("wrote \(url.path)")
