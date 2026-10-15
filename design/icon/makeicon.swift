// Writes the app icon as an Icon Composer document (Crema/AppIcon.icon) from the
// vector mark (crema-mark.svg), and the web export (docs/assets/icon.png)
// rendered from that document by Icon Composer's own `ictool`.
//
// The document is the only form of the icon the build ships: Xcode renders it
// with the system's Liquid Glass and generates the images for releases older
// than the material from the same file (Apple docs, "Creating your app icon
// using Icon Composer"). Its artwork stays two flat colours, the ground and the
// mark; the glass, its specular and its shadow are the system's, set here as
// the document's material, never drawn into the artwork.
//
// The document is generated, not edited in Icon Composer: an edit made there is
// overwritten by the next run, so a change to the material is a change to the
// values below. Icon Composer still opens the output to preview it.
//
// Run: swift design/icon/makeicon.swift
import AppKit

/// The mark's tight bounds take this share of the icon's width, centered.
let markShare: CGFloat = 0.56
/// Icon Composer's canvas, in points.
let canvas: CGFloat = 1024
/// The landing's tokens (docs/index.html): the ground is --raise #1b1610 and the
/// mark --cream #d6bd94, so the icon and the page share one palette.
let ground = "srgb:0.10588,0.08627,0.06275,1.00000"
let mark = "srgb:0.83922,0.74118,0.58039,1.00000"
/// The material, chosen on screen against the approved glass preview: the
/// ground's automatic gradient gives the slab its light, and a translucency
/// past this lets the ground muddy the mark's lower half.
let translucency = 0.3
let shadowOpacity = 0.5
/// The web export sits on the macOS icon grid, the body 824 of 1024, so the
/// README and the landing frame it as they framed every icon before it.
let webSide = 512
let webBodyShare: CGFloat = 824 / 1024

func markBounds(svg: URL) -> CGRect {
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
    return path.boundingBoxOfPath
}

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("\(tool) failed") }
}

let scriptDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let repo = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
let svg = scriptDir.appendingPathComponent("crema-mark.svg")
let document = repo.appendingPathComponent("Crema/AppIcon.icon")
let assets = document.appendingPathComponent("Assets")

// The mark is placed by its own bounds, so a redrawn mark keeps its share and
// its centre without a number changing here. Icon Composer centres the SVG's
// viewBox and translates in canvas points, x right and y down like the SVG
// (measured with ictool: +200, +200 moves the mark right and down by 200 pt).
let bounds = markBounds(svg: svg)
let scale = canvas * markShare / bounds.width
let dx = (canvas / 2 - bounds.midX) * scale
let dy = (canvas / 2 - bounds.midY) * scale

let fm = FileManager.default
try? fm.removeItem(at: document)
try! fm.createDirectory(at: assets, withIntermediateDirectories: true)
try! fm.copyItem(at: svg, to: assets.appendingPathComponent("crema-mark.svg"))

func fixed(_ value: CGFloat) -> String { String(format: "%.5f", Double(value)) }

let json = """
{
  "fill" : {
    "automatic-gradient" : "\(ground)"
  },
  "groups" : [
    {
      "layers" : [
        {
          "fill" : {
            "solid" : "\(mark)"
          },
          "glass" : true,
          "image-name" : "crema-mark.svg",
          "name" : "crema-mark",
          "position" : {
            "scale" : \(fixed(scale)),
            "translation-in-points" : [
              \(fixed(dx)),
              \(fixed(dy))
            ]
          }
        }
      ],
      "shadow" : {
        "kind" : "neutral",
        "opacity" : \(shadowOpacity)
      },
      "specular" : true,
      "translucency" : {
        "enabled" : true,
        "value" : \(translucency)
      }
    }
  ],
  "supported-platforms" : {
    "squares" : [
      "macOS"
    ]
  }
}

"""
try! json.write(to: document.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
print("wrote \(document.path)")

// The web export: Icon Composer's own rendering of the document, set on the
// icon grid's transparent margin.
let select = Process()
let selected = Pipe()
select.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
select.arguments = ["-p"]
select.standardOutput = selected
try! select.run()
select.waitUntilExit()
let developerPath = String(decoding: selected.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
let developer = URL(fileURLWithPath: developerPath.trimmingCharacters(in: .whitespacesAndNewlines))
let ictool = developer.deletingLastPathComponent()
    .appendingPathComponent("Applications/Icon Composer.app/Contents/Executables/ictool").path
let body = Int((CGFloat(webSide) * webBodyShare).rounded())
let rendered = fm.temporaryDirectory.appendingPathComponent("crema-icon-body.png")
run(ictool, [
    document.path, "--export-image", "--output-file", rendered.path,
    "--platform", "macOS", "--rendition", "Default",
    "--width", "\(body)", "--height", "\(body)", "--scale", "1",
])
guard let art = NSImage(contentsOf: rendered) else { fatalError("no ictool output") }
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: webSide, pixelsHigh: webSide, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0
)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let inset = CGFloat(webSide - body) / 2
art.draw(in: NSRect(x: inset, y: inset, width: CGFloat(body), height: CGFloat(body)))
NSGraphicsContext.restoreGraphicsState()
let web = repo.appendingPathComponent("docs/assets/icon.png")
try! rep.representation(using: .png, properties: [:])!.write(to: web)
try? fm.removeItem(at: rendered)
print("wrote \(web.path)")
