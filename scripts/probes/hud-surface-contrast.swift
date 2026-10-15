// How dark does a floating HUD surface stay over the desktop behind it, and
// does Liquid Glass do better in a panel that is never key?
//
// Card and Classic draw on the hudWindow vibrancy material under a black film
// (SurfaceChrome.scrimOpacity, Crema/Styles/VibrantSurface.swift), with white
// ink. The material alone takes on what is behind it; the film keeps the ink
// readable over the worst case, a white page. Liquid Glass is the standing
// alternative (docs/DECISIONS.md: hud-fixed-dark-palette), so it is measured
// beside it, on the same kind of panel Crema uses.
//
// It shows one bar per variant over a backdrop, captures the screen with
// `screencapture` (Screen Recording permission), and prints each bar's surface
// colour and the contrast of the ink drawn on it:
//   1. material, white ink (the film at 0: the control)
//   2. material + film at the given opacity, white ink (what ships)
//   3. glassEffect(.regular), never-key panel, white ink, dark scheme
//   4. glassEffect(.regular), never-key panel, semantic ink, system scheme
//   5. NSGlassEffectView, never-key panel, semantic ink, system scheme
//
// Measured with this probe 2026-10-15, macOS 27.0.1, MacBook Pro 14", system in
// Light appearance, film 0.44. Ink contrast over white / black:
//   1. 2.0:1 / 16:1    2. 4.8:1 / 19:1    3. 1.8:1 / 17:1
//   4. 1.5:1 / 2.0:1   5. 1.5:1 / 2.0:1
// Never-key glass draws no specular edge (a key window's does), and its
// semantic ink follows the system appearance, not the backdrop: in Light, pale
// glass over white and mid-grey glass over black, the ink faint on both. Invalidated by never-key glass drawing its edge, or by
// variant 4 or 5 reaching 4.5:1 over both backdrops.
//
// Read-only: it opens its own windows for a few seconds and writes nothing but
// a temporary capture.
//
// Run: swift scripts/probes/hud-surface-contrast.swift white|black|gradient [film]
import AppKit
import SwiftUI

let backdropKind = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "white"
let film = CommandLine.arguments.count > 2 ? Double(CommandLine.arguments[2])! : 0.44
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class NeverKeyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

struct Bar: View {
    var semantic = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(semantic ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
            Capsule()
                .fill(semantic ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
                .frame(height: 4)
        }
        .padding(.horizontal, 16)
        .frame(width: 220, height: 38)
    }
}

struct Vibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

let shape = RoundedRectangle(cornerRadius: 12.67, style: .continuous)
let origin = NSPoint(x: 200, y: 400)
let columns: [CGFloat] = (0..<5).map { 30 + CGFloat($0) * 250 }

func show(_ content: NSView, column: Int) {
    let panel = NeverKeyPanel(
        contentRect: NSRect(x: origin.x + columns[column], y: origin.y + 60, width: 220, height: 38),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    panel.contentView = content
    panel.orderFrontRegardless()
}

final class Fill: NSView {
    override func draw(_ dirty: NSRect) {
        switch backdropKind {
        case "black":
            NSColor.black.setFill()
            bounds.fill()
        case "gradient":
            NSGradient(colors: [.systemBlue, .systemOrange, .white])!.draw(in: bounds, angle: 0)
        default:
            NSColor.white.setFill()
            bounds.fill()
        }
    }
}

let backdrop = NSWindow(
    contentRect: NSRect(x: origin.x, y: origin.y, width: 1300, height: 160),
    styleMask: .borderless,
    backing: .buffered,
    defer: false
)
backdrop.level = .floating
backdrop.contentView = Fill()
backdrop.orderFrontRegardless()

func hosting(_ view: some View) -> NSView { NSHostingView(rootView: view) }

show(hosting(Bar().background { Vibrancy() }.clipShape(shape).environment(\.colorScheme, .dark)), column: 0)
show(hosting(Bar().background { ZStack { Vibrancy(); Color.black.opacity(film) } }.clipShape(shape)
        .environment(\.colorScheme, .dark)), column: 1)
show(hosting(Bar().glassEffect(.regular, in: shape).environment(\.colorScheme, .dark)), column: 2)
show(hosting(Bar(semantic: true).glassEffect(.regular, in: shape)), column: 3)
let glass = NSGlassEffectView()
glass.cornerRadius = 12.67
glass.contentView = hosting(Bar(semantic: true))
show(glass, column: 4)

func luminance(_ color: NSColor) -> Double {
    func channel(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(color.redComponent) + 0.7152 * channel(color.greenComponent)
        + 0.0722 * channel(color.blueComponent)
}

func average(_ rep: NSBitmapImageRep, x: Int, y: Int, radius: Int) -> NSColor {
    var sum = [0.0, 0.0, 0.0]
    var count = 0.0
    for dx in -radius...radius {
        for dy in -radius...radius {
            let c = rep.colorAt(x: x + dx, y: y + dy)!.usingColorSpace(.sRGB)!
            sum[0] += c.redComponent
            sum[1] += c.greenComponent
            sum[2] += c.blueComponent
            count += 1
        }
    }
    return NSColor(srgbRed: sum[0] / count, green: sum[1] / count, blue: sum[2] / count, alpha: 1)
}

DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
    let screenHeight = NSScreen.screens[0].frame.height
    let top = Int(screenHeight - origin.y - 160)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("hud-surface-contrast.png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-R\(Int(origin.x)),\(top),1300,160", file.path]
    try! capture.run()
    capture.waitUntilExit()
    let rep = NSBitmapImageRep(data: try! Data(contentsOf: file))!
    let scale = Double(rep.pixelsWide) / 1300
    let names = ["material", "material + film \(film)", "glass, white ink", "glass, semantic ink", "NSGlassEffectView, semantic"]
    for (i, x) in columns.enumerated() {
        // The bar spans 62–100 pt down the capture: the surface is read above the
        // track near the trailing end, the ink on the track at the bar's middle.
        let surface = average(rep, x: Int((x + 212) * scale), y: Int(70 * scale), radius: 3)
        let ink = average(rep, x: Int((x + 120) * scale), y: Int(81 * scale), radius: 1)
        let (a, b) = (luminance(surface), luminance(ink))
        let ratio = (max(a, b) + 0.05) / (min(a, b) + 0.05)
        print(String(format: "%d. %@ over %@: surface %.0f%% grey, ink contrast %.2f:1",
                     i + 1, names[i], backdropKind, surface.brightnessComponent * 100, ratio))
    }
    try? FileManager.default.removeItem(at: file)
    exit(0)
}

app.run()
