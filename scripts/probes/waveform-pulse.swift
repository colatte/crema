// Does the compact player's waveform keep pulsing through each transition the
// surface goes through, or does it stop?
//
// The pulse is one implicit `repeatForever` per bar (Crema/Styles/WaveformGlyph.swift),
// and an animation the surface starts around it can replace it: a stopped pulse
// shows as the four bars frozen at the peak, all equal. A track change with the
// Card on screen does that when the Card's width spring reaches the bars (the
// rationale at `geometryGroup()` in the glyph).
//
// Run it against a Debug copy with its own bundle id, so its preferences never
// touch the installed app's, on the demo sources (Crema/App/DemoRemote.swift):
//
//   xcodebuild -project Crema.xcodeproj -scheme Crema -configuration Debug \
//     -derivedDataPath /tmp/crema-probe PRODUCT_BUNDLE_IDENTIFIER=com.colatte.crema.probe build
//   /tmp/crema-probe/Build/Products/Debug/Crema.app/Contents/MacOS/Crema \
//     -CremaUseDemoSources YES -hasSeenWelcomeTour YES &
//   swift scripts/probes/waveform-pulse.swift $! [card|notch|classic]
//
// REQUIRES SCREEN RECORDING for the process that runs the probe (Terminal, iTerm,
// Xcode): without it the captures hold no surface and every case reads "no bars".
// The copy is driven through its own surface, which appears on screen while this
// runs; the probe quits it at the end. `defaults delete com.colatte.crema.probe`
// clears the style it leaves in that copy's domain.
//
// Each case runs five times from a pulsing glyph and samples the bars twelve times.
// FROZEN means every sample was identical. The ranges are each bar's lowest and
// highest height in points, to read against `WaveformGlyph.Configuration.standard`;
// a sample with a bar missing does not count, so "(n/12 frames)" is a bar that
// dipped out of sight. A cover with no usable tone draws neutral bars, which the
// saturation test cannot see, and its track reads "no bars".
//
// The controls pulse whatever the case under test does: pause/play with the
// surface up (the glyph's own `dancing` flip) and a HUD over the player and back
// (the glyph remounted). A run where a control freezes is a broken probe or
// capture, not a finding about the case under test.

import AppKit
import CoreGraphics
import Foundation

guard let pid = CommandLine.arguments.dropFirst().first.flatMap(Int32.init) else {
    print("usage: swift scripts/probes/waveform-pulse.swift <pid of a demo Crema> [card|notch|classic]")
    exit(2)
}

let style = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "card"
let scale = NSScreen.main?.backingScaleFactor ?? 2

/// One line to the demo's remote, as scripts/site-capture/post.swift sends it.
func say(_ line: String) {
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.colatte.crema.demo"), object: line, userInfo: nil, deliverImmediately: true
    )
}

func wait(_ seconds: Double) {
    Thread.sleep(forTimeInterval: seconds)
}

/// The copy's largest on-screen window: the surface's panel, which is never
/// ordered out, so `screencapture -l` takes it alone whatever covers it.
func panelWindowID() -> CGWindowID? {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    let area = { (window: [String: Any]) -> Double in
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    }
    return windows
        .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
        .max { area($0) < area($1) }?[kCGWindowNumber as String] as? CGWindowID
}

/// The bars' heights in points, left to right, or nil when no waveform is drawn.
/// A bar is one connected region of bright, saturated pixels (the cover's tone),
/// and the waveform is four narrow ones on one centre line, evenly spaced: the
/// bars are centre-anchored, so their centres agree whatever their heights. The
/// cover, saturated too, is one wide region, and regions rather than columns
/// keep it apart where a skin stacks the bars under it (Classic).
func barHeights(window: CGWindowID) -> [Double]? {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("waveform-pulse.png")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l\(window)", file.path]
    guard (try? capture.run()) != nil else { return nil }
    capture.waitUntilExit()
    guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }

    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    func lit(_ x: Int, _ y: Int) -> Bool {
        let i = (y * width + x) * 4
        let channels = [Double(pixels[i]), Double(pixels[i + 1]), Double(pixels[i + 2])]
        let brightest = channels.max() ?? 0, dimmest = channels.min() ?? 0
        return brightest > 90 && (brightest - dimmest) / brightest > 0.3
    }

    var seen = [Bool](repeating: false, count: width * height)
    var regions: [CGRect] = []
    for start in 0..<(width * height) where !seen[start] && lit(start % width, start / width) {
        seen[start] = true
        var pending = [start]
        var minX = width, maxX = 0, minY = height, maxY = 0
        while let index = pending.popLast() {
            let x = index % width, y = index / width
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where (0..<width).contains(nx) && (0..<height).contains(ny) {
                let next = ny * width + nx
                if !seen[next], lit(nx, ny) {
                    seen[next] = true
                    pending.append(next)
                }
            }
        }
        regions.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
    }

    let narrow = regions.filter { $0.width <= 3 * scale }.sorted { $0.minX < $1.minX }
    guard narrow.count >= 4 else { return nil }
    for start in 0...(narrow.count - 4) {
        let group = Array(narrow[start..<(start + 4)])
        let pitches = zip(group, group.dropFirst()).map { $1.minX - $0.minX }
        let centres = group.map(\.midY)
        guard let widestPitch = pitches.max(), let narrowestPitch = pitches.min(),
              let lowestCentre = centres.min(), let highestCentre = centres.max() else { continue }
        if widestPitch - narrowestPitch <= 2, highestCentre - lowestCentre <= 2 {
            return group.map { Double($0.height) / scale }
        }
    }
    return nil
}

/// Twelve samples of the bars, summarised.
func verdict(window: CGWindowID) -> String {
    let samples = (0..<12).compactMap { _ in barHeights(window: window) }
    guard let first = samples.first else { return "no bars" }
    let ranges = first.indices.map { bar in
        let heights = samples.map { $0[bar] }
        return String(format: "%4.1f-%-4.1f", heights.min() ?? 0, heights.max() ?? 0)
    }.joined(separator: "  ")
    let frozen = samples.count > 1 && samples.allSatisfy { $0 == first }
    return ranges + (frozen ? "  FROZEN" : "") + (samples.count < 12 ? "  (\(samples.count)/12 frames)" : "")
}

say("style \(style)")
wait(1.5)
say("play")
wait(0.6)
guard let window = panelWindowID() else {
    print("no window for pid \(pid): is it a demo Crema, launched as the header says?")
    exit(1)
}

/// Every wait below outlasts a timer of the Coordinator's: the HUD's revert
/// (`defaultHUDRevertDelay`) or the reactive appearance's linger
/// (`defaultNowPlayingLinger`).
let cases: [(name: String, act: () -> Void)] = [
    ("control: pause/play, surface up", { say("pause"); wait(0.4); say("play"); wait(0.5) }),
    ("control: HUD over the player and back", { say("hud volume 0.5"); wait(2.0) }),
    ("track change, surface up", { say("next"); wait(0.5) }),
    ("reappearance after the tuck", { say("pause"); wait(3.6); say("play"); wait(0.5) }),
]

print("style \(style), scale \(scale), bar ranges in pt (bar 1 … bar 4)")
for test in cases {
    print(test.name)
    for trial in 1...5 {
        // Every trial starts from a pulsing glyph with the surface up.
        say("pause"); wait(0.4); say("play"); wait(0.5)
        test.act()
        print("  \(trial): \(verdict(window: window))")
    }
}

say("quit")
