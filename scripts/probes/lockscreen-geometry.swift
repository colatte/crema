// Where is the lock screen's own UI, in points, on THIS Mac?
//
// The lock widget was positioned from a mock: 96 pt off the bottom, with a
// comment claiming that clears "the avatar and the password field, which own
// the middle and the low centre". Nobody measured it. On hardware the expanded
// cover landed on top of both, which means the comment was not merely unproven,
// it was backwards — macOS moved the login UI DOWN in Sonoma (the clock went to
// the top and the user tile to the bottom section), so a card pinned to the
// bottom is pinned exactly where the password field now lives.
//
// Blog posts disagree with each other and none of them are about macOS 26, so
// this asks the screen instead. It draws a ruler over the shield and a set of
// candidate card positions; the author looks and says which are clear.
//
// AND THE MEASUREMENT IS NOT THE ANSWER — that is the point of the horizontal
// half of this probe. A y offset measured here is correct on this macOS and
// wrong on the next one: Sonoma already moved the login UI from the middle to
// the bottom, and nothing stops 27 from moving it again. A number read off this
// ruler and frozen into `LockWidgetMetrics` would be the same kind of claim as
// the comment that started this.
//
// What does NOT move is the horizontal axis. The user tile, the name and the
// password field have been CENTRED in every version; what changed was how far
// down. So the durable rule is not "sit at y=N", it is "stay out of the centre
// column" — a structural property rather than a measurement. This probe
// therefore measures the column's WIDTH as well as the login UI's height, and
// offers corner candidates beside the centred ones. If a corner is clear here,
// it is clear for reasons that survive a redesign.
//
// WHAT YOU SEE, all of it click-through so the lock screen keeps every click:
//
//   · A horizontal line every 5% of screen height, labelled on BOTH sides with
//     the AppKit y coordinate (origin bottom-left, y up — the space every frame
//     rule in this app speaks) and the distance from the bottom edge.
//   · A vertical centre line, and a dashed 520 pt band around it: the column
//     the login UI is presumed never to leave. Whether it actually stays inside
//     is the question the corner candidates depend on.
//   · Six candidates at the card's real collapsed size. A / B / C are CENTRED
//     at 96 / 220 / 340 pt from the bottom — A is what ships today. E / F / G
//     are CORNERS: bottom-left, bottom-right, top-left.
//   · A 300 pt square outlined at screen centre: the expanded cover, drawn
//     where the code puts it today.
//
// WHAT TO REPORT BACK:
//   1. The y range the avatar + name + password field occupy (read it off the
//      nearest labelled lines).
//   2. The y range of the clock at the top.
//   3. Which of A / B / C and E / F / G are completely clear of both.
//   4. Whether anything of the login UI crosses OUT of the orange column —
//      this is the one that decides whether a corner is safe by construction or
//      just safe today.
//   5. Whether the red 300 pt square overlaps anything.
//
// Run:  swift scripts/probes/lockscreen-geometry.swift
// Then: lock (Control-Command-Q), read, unlock. Ctrl-C to end.
//
// Read-only with respect to the app: no preference, no display, no key. The
// window is ignoresMouseEvents, so it cannot take a click from the login UI.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.screens.first else {
    print("no screen"); exit(1)
}
let frame = screen.frame

// MARK: - The ruler

final class RulerView: NSView {
    /// The card's real collapsed size, so a candidate is not a rectangle in the
    /// abstract but the thing that would actually be drawn.
    static let cardSize = CGSize(width: 340, height: 152)
    static let heroSide: CGFloat = 300

    /// Distance from the bottom edge for each candidate. The first is what
    /// ships today; the rest climb out of the way.
    static let candidates: [(String, CGFloat)] = [
        ("A", 96), ("B", 220), ("C", 340),
    ]

    override var isFlipped: Bool { false }

    override func draw(_ dirty: NSRect) {
        let h = bounds.height, w = bounds.width

        NSColor.black.withAlphaComponent(0.28).setFill()
        bounds.fill()

        // Every 5% of the height, labelled on both sides.
        for step in 0...20 {
            let fraction = CGFloat(step) / 20
            let y = h * fraction
            let major = step % 4 == 0
            (major ? NSColor.systemYellow : NSColor.white.withAlphaComponent(0.35)).setStroke()
            let line = NSBezierPath()
            line.lineWidth = major ? 1.5 : 0.75
            line.move(to: CGPoint(x: 0, y: y))
            line.line(to: CGPoint(x: w, y: y))
            line.stroke()

            let label = "y=\(Int(y))  ·  \(Int(fraction * 100))%  ·  \(Int(y)) from bottom"
            draw(label, at: CGPoint(x: 12, y: y + 3), size: major ? 13 : 10,
                 color: major ? .systemYellow : .white)
            draw(label, at: CGPoint(x: w - 260, y: y + 3), size: major ? 13 : 10,
                 color: major ? .systemYellow : .white)
        }

        // The centre line: the login UI and the card are both centred, so
        // overlap is a question about y only.
        NSColor.systemYellow.withAlphaComponent(0.5).setStroke()
        let centre = NSBezierPath()
        centre.lineWidth = 1
        centre.move(to: CGPoint(x: w / 2, y: 0))
        centre.line(to: CGPoint(x: w / 2, y: h))
        centre.stroke()

        // CENTRED candidates — the shape that ships today, and the one whose
        // safety expires with the next macOS layout change.
        for (name, bottom) in Self.candidates {
            outline(
                CGRect(x: (w - Self.cardSize.width) / 2, y: bottom,
                       width: Self.cardSize.width, height: Self.cardSize.height),
                label: "\(name) — CENTRED, \(Int(bottom)) pt from bottom",
                color: .systemGreen
            )
        }

        // CORNER candidates — out of the column the login UI has occupied in
        // every version. If one of these is clear, it is clear structurally
        // rather than by a number that happens to hold today.
        let margin: CGFloat = 40
        outline(
            CGRect(x: margin, y: margin,
                   width: Self.cardSize.width, height: Self.cardSize.height),
            label: "E — BOTTOM-LEFT corner", color: .systemTeal
        )
        outline(
            CGRect(x: w - Self.cardSize.width - margin, y: margin,
                   width: Self.cardSize.width, height: Self.cardSize.height),
            label: "F — BOTTOM-RIGHT corner", color: .systemTeal
        )
        outline(
            CGRect(x: margin, y: h - Self.cardSize.height - margin,
                   width: Self.cardSize.width, height: Self.cardSize.height),
            label: "G — TOP-LEFT corner", color: .systemTeal
        )

        // How wide the centre column has to be avoided for. Drawn as the band a
        // corner candidate must clear, so the answer is readable rather than
        // arithmetic: report where the login UI's widest element ends.
        let column = CGRect(x: (w - 520) / 2, y: 0, width: 520, height: h)
        NSColor.systemOrange.withAlphaComponent(0.10).setFill()
        column.fill()
        NSColor.systemOrange.withAlphaComponent(0.6).setStroke()
        let columnPath = NSBezierPath(rect: column)
        columnPath.lineWidth = 2
        columnPath.setLineDash([8, 6], count: 2, phase: 0)
        columnPath.stroke()
        draw("centre column, 520 pt wide — does the login UI stay inside it?",
             at: CGPoint(x: column.minX + 8, y: h * 0.62), size: 14, color: .systemOrange)

        // The expanded cover, where the code puts it today: centred.
        let hero = CGRect(
            x: (w - Self.heroSide) / 2, y: (h - Self.heroSide) / 2,
            width: Self.heroSide, height: Self.heroSide
        )
        NSColor.systemRed.setStroke()
        let heroPath = NSBezierPath(roundedRect: hero, xRadius: 24, yRadius: 24)
        heroPath.lineWidth = 4
        heroPath.stroke()
        draw("expanded cover, 300 pt, screen centre — WHERE IT IS TODAY",
             at: CGPoint(x: hero.minX - 40, y: hero.maxY + 10), size: 15, color: .systemRed)

        draw("screen \(Int(w))×\(Int(h)) pt   ·   report: y range of avatar/password, y range of clock, which of A-C / E-G are clear, and whether the login UI leaves the orange column",
             at: CGPoint(x: 12, y: h - 28), size: 13, color: .white)
    }

    private func outline(_ rect: CGRect, label: String, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        path.lineWidth = 3
        path.stroke()
        color.withAlphaComponent(0.15).setFill()
        path.fill()
        draw(label, at: CGPoint(x: rect.minX + 10, y: rect.midY - 8), size: 14, color: color)
    }

    private func draw(_ text: String, at point: CGPoint, size: CGFloat, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
            .foregroundColor: color,
            .backgroundColor: NSColor.black.withAlphaComponent(0.55),
        ]
        NSAttributedString(string: " \(text) ", attributes: attributes).draw(at: point)
    }
}

let panel = NSPanel(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.canBecomeVisibleWithoutLogin = true
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
// Non-negotiable: a ruler that ate the password field would be a probe that
// locks you out of your Mac.
panel.ignoresMouseEvents = true
panel.contentView = RulerView(frame: CGRect(origin: .zero, size: frame.size))

// MARK: - The raised space (the five calls the app makes)

typealias MainConnectionID = @convention(c) () -> Int32
typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)

func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let skylight, let p = dlsym(skylight, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

if let cidFn = sym("SLSMainConnectionID", MainConnectionID.self),
   let create = sym("SLSSpaceCreate", SpaceCreate.self),
   let setLevel = sym("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
   let show = sym("SLSShowSpaces", ShowSpaces.self),
   let addWindows = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddWindows.self) {
    let cid = cidFn()
    let space = create(cid, 1, 0)
    _ = setLevel(cid, space, 400)
    _ = show(cid, [space] as CFArray)
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    _ = addWindows(cid, space, [panel.windowNumber] as CFArray, 7)
    print("ruler up on a raised space, screen \(Int(frame.width))×\(Int(frame.height)) pt")
} else {
    print("SkyLight did not resolve — the ruler will not survive the lock")
    panel.orderFrontRegardless()
}

print("""
Lock the screen (Control-Command-Q) and read the ruler. Report:
  1. the y range the avatar + name + password field occupy
  2. the y range of the clock at the top
  3. which of A / B / C (centred) and E / F / G (corners) are completely clear
  4. whether the login UI stays inside the dashed orange centre column
  5. whether the red 300 pt square overlaps anything
Ctrl-C to end.
""")
app.run()
