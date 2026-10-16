// Prints the id of the largest ordinary window a process has on screen: the
// welcome tour's, for screencapture -l, which captures it whatever covers it.
import CoreGraphics
import Foundation

let pid = Int32(CommandLine.arguments[1]) ?? -1
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
let mine = windows.filter {
    ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
}

let largest = mine.max { a, b in
    let area = { (w: [String: Any]) -> Double in
        let bounds = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
        return (bounds["Width"] ?? 0) * (bounds["Height"] ?? 0)
    }
    return area(a) < area(b)
}

if let id = largest?[kCGWindowNumber as String] { print(id) } else { exit(1) }
