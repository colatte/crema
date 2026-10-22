// What does the native OSD's edge look like, and how light is its body?
//
// Liquid Glass in a never-key panel draws no rim of its own (measured with
// scripts/probes/hud-surface-contrast.swift), so the Card's glass strokes one
// (SurfaceChrome.glassRimStops). This reads that rim off a capture of the
// system's own volume OSD: press a volume key with Crema's replacement off,
// screenshot the OSD over a black page, and point this at the PNG with a column
// that crosses the box top to bottom. It prints every change in tone down that
// column, so the top edge, the body and the bottom edge read off directly; run it
// again on a row to read the sides.
//
// Measured 2026-10-22, macOS 27.0.1, MacBook Pro 14" (2x), the OSD over a black
// page, column x=600: body #1a–#21; edge pixels #66 at the top and #55 at the
// bottom (row y=110: #44 left, #3b right). Over the body that is white at about
// 0.32 at the top, 0.25 at the bottom and 0.17 at the sides. Over a white page
// the same OSD's body reads #d1–#d9 under white ink, about 1.5:1. A capture whose
// edge reads differently invalidates the stops.
//
// Run: swift scripts/probes/native-osd-edge.swift <capture.png> col|row <index>

import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4, let index = Int(arguments[3]),
      let data = FileManager.default.contents(atPath: arguments[1]),
      let rep = NSBitmapImageRep(data: data)
else {
    print("usage: native-osd-edge.swift <capture.png> col|row <index>")
    exit(1)
}

func gray(_ x: Int, _ y: Int) -> Int {
    guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return -1 }
    return Int(((color.redComponent + color.greenComponent + color.blueComponent) / 3 * 255).rounded())
}

let alongColumn = arguments[2] == "col"
let length = alongColumn ? rep.pixelsHigh : rep.pixelsWide
var last = -100
for step in 0..<length {
    let value = alongColumn ? gray(index, step) : gray(step, index)
    if abs(value - last) > 6 {
        print(alongColumn ? "y=\(step)" : "x=\(step)", String(format: "#%02x", value))
        last = value
    }
}
