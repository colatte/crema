// The stage the site's captures are taken on: every screen covered by a
// wallpaper of our own, a plain menu bar and, on a screen with a notch, the
// notch drawn where the hardware is, so nothing of the Mac running the
// capture (its wallpaper, windows, menu bar items) reaches a published image.
// Above the menu bar and the Dock, below Crema's panels (.mainMenu + 3).
// Runs until killed.
import AppKit

final class Stage: NSView {
    let notch: CGRect?
    let barHeight: CGFloat
    let mark: NSImage?

    init(frame: CGRect, notch: CGRect?, barHeight: CGFloat, mark: NSImage?) {
        self.notch = notch
        self.barHeight = barHeight
        self.mark = mark
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirty: NSRect) {
        let b = bounds
        NSGradient(colors: [
            NSColor(srgbRed: 0.29, green: 0.19, blue: 0.13, alpha: 1),
            NSColor(srgbRed: 0.23, green: 0.16, blue: 0.20, alpha: 1),
            NSColor(srgbRed: 0.15, green: 0.13, blue: 0.21, alpha: 1),
        ])?.draw(in: b, angle: 80)
        for (x, y, r, color) in [
            (0.18, 0.78, 0.55, NSColor(srgbRed: 0.48, green: 0.38, blue: 0.66, alpha: 0.55)),
            (0.84, 0.82, 0.5, NSColor(srgbRed: 0.27, green: 0.41, blue: 0.59, alpha: 0.5)),
            (0.72, 0.08, 0.7, NSColor(srgbRed: 0.77, green: 0.47, blue: 0.28, alpha: 0.6)),
            (0.16, 0.1, 0.55, NSColor(srgbRed: 0.59, green: 0.28, blue: 0.25, alpha: 0.45)),
        ] {
            let center = CGPoint(x: b.width * x, y: b.height * y)
            NSGradient(colors: [color, color.withAlphaComponent(0)])?
                .draw(fromCenter: center, radius: 0, toCenter: center, radius: max(b.width, b.height) * r, options: [])
        }

        let bar = CGRect(x: 0, y: b.height - barHeight, width: b.width, height: barHeight)
        NSColor.black.withAlphaComponent(0.18).setFill()
        bar.fill()
        let font = NSFont.systemFont(ofSize: 13)
        let ink = NSColor.white.withAlphaComponent(0.92)
        var x: CGFloat = 20
        for (i, word) in ["Finder", "File", "Edit", "View"].enumerated() {
            if let notch, x > notch.minX - 70 { break }
            let attributes: [NSAttributedString.Key: Any] = [.font: i == 0 ? NSFont.boldSystemFont(ofSize: 13) : font, .foregroundColor: ink]
            let text = NSAttributedString(string: word, attributes: attributes)
            text.draw(at: CGPoint(x: x, y: bar.midY - text.size().height / 2))
            x += text.size().width + 20
        }
        let clock = NSAttributedString(string: "Thu 9:41", attributes: [.font: font, .foregroundColor: ink])
        let clockX = b.width - 18 - clock.size().width
        clock.draw(at: CGPoint(x: clockX, y: bar.midY - clock.size().height / 2))
        if let mark {
            let side: CGFloat = 16
            mark.draw(in: CGRect(x: clockX - 26 - side, y: bar.midY - side / 2, width: side, height: side))
        }

        if let notch {
            NSColor.black.setFill()
            NSBezierPath(roundedRect: notch.insetBy(dx: 0, dy: -10).offsetBy(dx: 0, dy: 10), xRadius: 9, yRadius: 9).fill()
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let markURL = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "design/icon/crema-mark.svg")
let mark: NSImage? = {
    guard let source = NSImage(contentsOf: markURL) else { return nil }
    return NSImage(size: source.size, flipped: false) { rect in
        source.draw(in: rect)
        NSColor.white.setFill()
        rect.fill(using: .sourceAtop)
        return true
    }
}()

var windows: [NSWindow] = []
for screen in NSScreen.screens {
    let frame = screen.frame
    var notch: CGRect?
    if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
        notch = CGRect(x: left.maxX, y: frame.height - left.height, width: right.minX - left.maxX, height: left.height)
    }
    let barHeight = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : NSStatusBar.system.thickness
    let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
    window.ignoresMouseEvents = true
    window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
    window.contentView = Stage(frame: CGRect(origin: .zero, size: frame.size), notch: notch, barHeight: barHeight, mark: mark)
    window.setFrame(frame, display: true)
    window.orderFrontRegardless()
    windows.append(window)
    print("screen \(screen.localizedName) frame=\(frame) bar=\(barHeight) notch=\(notch.map { "\($0)" } ?? "none")")
}

signal(SIGTERM) { _ in exit(0) }
app.run()
