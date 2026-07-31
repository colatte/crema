// One keypress, how many displays move?
//
// The field report: with the new build, the bar appears but the BUILT-IN screen is
// what visibly changes, while BetterDisplay's payload names the external. Two very
// different causes, and they need different fixes:
//
//   (a) BetterDisplay acts on the external and does NOT consume the key, so Crema
//       receives it too and writes its own actuator — the built-in. Two displays
//       move per press, and the bar describes only one of them.
//   (b) Only the built-in moves, and BetterDisplay's payload is reporting a display
//       it did not actually change.
//
// This samples the built-in's real level through DisplayServices while listening to
// BetterDisplay's channel, so one run says which. Read-only: it never writes.
//
// Run:  swift scripts/probes/who-moves-what.swift    then press F1/F2

import AppKit
import CoreGraphics
import Foundation

func activeDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &n) == .success, n > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    guard CGGetActiveDisplayList(n, &ids, &n) == .success else { return [] }
    return Array(ids.prefix(Int(n)))
}

let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
typealias DSGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
guard let dsGet = dlsym(handle, "DisplayServicesGetBrightness").map({ unsafeBitCast($0, to: DSGet.self) }) else {
    print("DisplayServicesGetBrightness did not resolve — cannot sample.")
    exit(1)
}

func builtInLevel() -> Float? {
    guard let id = activeDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
    var v: Float = 0
    return dsGet(id, &v) == 0 ? v : nil
}

let start = Date()
func stamp() -> String { String(format: "%5.1fs", Date().timeIntervalSince(start)) }

/// Which display the pointer is over, and which one carries the menu bar. Printed
/// with every event because the neighbour decides per keypress whether to consume,
/// and these are the two candidates for what it decides on: same chain order and
/// same build produced opposite outcomes an hour apart, so the variable is on its
/// side, not ours.
func context() -> String {
    let point = NSEvent.mouseLocation
    let under = NSScreen.screens.first { $0.frame.contains(point) }
    let number = under?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let cursorID = number?.uint32Value ?? 0
    let main = CGMainDisplayID()
    return "cursor on display \(cursorID) (\(under?.localizedName ?? "?")), menu bar on \(main)"
}

DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("pro.betterdisplay.BetterDisplay.osd"),
    object: nil,
    queue: .main
) { note in
    guard let json = note.object as? String,
          let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    let target = obj["controlTarget"] as? String ?? "?"
    let display = obj["displayID"] as? Int ?? -1
    let value = obj["value"] as? Double ?? -1
    let maxValue = obj["maxValue"] as? Double ?? -1
    let ratio = maxValue > 0 ? value / maxValue : -1
    print("\(stamp())  NEIGHBOUR says: display \(display) \(target) = \(value)/\(maxValue) (\(String(format: "%.3f", ratio)))  [\(context())]")
}

// Poll the built-in fast enough to catch a step, and print only real changes.
var last = builtInLevel()
print("built-in level at start: \(last.map { String(format: "%.3f", $0) } ?? "unreadable")")
print("context at start: \(context())")
print("watching for 30 s — press F1/F2 a few times\n")

let deadline = Date().addingTimeInterval(30)
let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
    guard let now = builtInLevel() else { return }
    if let previous = last, abs(now - previous) > 0.0005 {
        print("\(stamp())  BUILT-IN moved: \(String(format: "%.3f", previous)) -> \(String(format: "%.3f", now))  [\(context())]")
    }
    last = now
}

RunLoop.main.add(timer, forMode: .default)
while Date() < deadline { RunLoop.main.run(mode: .default, before: deadline) }
timer.invalidate()

print("\n=== how to read this")
print("BUILT-IN moved lines interleaved with NEIGHBOUR lines  -> cause (a): both act on")
print("  one press. Crema swallowed the key and wrote its own display while the")
print("  neighbour drove the external, and the bar describes only the neighbour's.")
print("ONLY NEIGHBOUR lines, built-in still  -> the external really is what moves, and")
print("  the visible change was somewhere else.")
print("ONLY BUILT-IN lines  -> the neighbour reports a display it does not drive.")
