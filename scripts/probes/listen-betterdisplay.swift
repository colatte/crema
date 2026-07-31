// Is BetterDisplay actually publishing its OSD notification right now?
//
// The integration is "by evidence, never by presence": the app running proves
// nothing, only a delivered payload does. This listens on the exact name for 25 s
// and prints whatever arrives. Press the brightness keys while it runs.
//
// Run:  swift scripts/probes/listen-betterdisplay.swift
//
// Exact name, never nil: macOS silently drops a DistributedNotificationCenter
// observation registered with a nil name, so a wildcard listener is deaf by
// construction — that cost two blind probes to learn. And only ONE prefix: the
// same event is published under the current and the legacy name, so observing
// both doubles everything.

import AppKit
import Foundation

let name = "pro.betterdisplay.BetterDisplay.osd"
var received = 0

DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name(name),
    object: nil,
    queue: .main
) { note in
    received += 1
    print("\n[\(received)] payload:")
    // The payload arrives as a JSON string in `object`, not in userInfo — the
    // third thing that cost a probe to discover.
    if let json = note.object as? String {
        print("  object (JSON string): \(json)")
        if let data = json.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in obj.sorted(by: { $0.key < $1.key }) {
                print("    \(k) = \(v)")
            }
            if let raw = obj["displayID"] as? Int { report(displayID: raw) }
        }
    } else {
        print("  object: \(String(describing: note.object))")
    }
    if let info = note.userInfo, !info.isEmpty {
        print("  userInfo: \(info)")
    }
}

// What the app does with a reported displayID, reproduced here: the border
// resolves BetterDisplay's raw CGDirectDisplayID to the UUID the domain keys by,
// over the ACTIVE display list — and a display it cannot name is dropped, because
// a bar for a screen the app cannot place is one it can neither draw nor send a
// drag back to. Then the HUD is scoped to that display's own panel
// (docs/DECISIONS.md: hud-belongs-to-its-display), so a display with no panel is
// a bar drawn nowhere. Both are printed, because they are different failures.
func activeDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &n) == .success, n > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    guard CGGetActiveDisplayList(n, &ids, &n) == .success else { return [] }
    return Array(ids.prefix(Int(n)))
}

func uuid(of id: CGDirectDisplayID) -> String? {
    CGDisplayCreateUUIDFromDisplayID(id).map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String }
}

func report(displayID raw: Int) {
    let id = CGDirectDisplayID(raw)
    let isActive = activeDisplays().contains(id)
    let resolved = isActive ? uuid(of: id) : nil
    print("    -> active in CGGetActiveDisplayList: \(isActive)")
    print("    -> resolves to UUID: \(resolved ?? "NO  <- the border drops this payload here")")
    let onRoster = NSScreen.screens.contains { screen in
        let n = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        return CGDirectDisplayID(n?.uint32Value ?? 0) == id
    }
    print("    -> on the NSScreen roster (so it has a panel): \(onRoster)\(onRoster ? "" : "  <- a HUD naming it would draw nowhere")")
}

let running = NSWorkspace.shared.runningApplications
    .contains { $0.bundleIdentifier == "pro.betterdisplay.BetterDisplay" }
print("BetterDisplay running (by bundle ID, never the localized name): \(running)")
print("screens macOS reports right now: \(NSScreen.screens.map(\.localizedName))")
print("active display IDs: \(activeDisplays())")
print("listening on \(name) for 25 s — press F1/F2 now")

let deadline = Date().addingTimeInterval(25)
while Date() < deadline {
    RunLoop.main.run(mode: .default, before: deadline)
}

print("\n=== \(received) notification(s) in 25 s")
if received == 0 {
    print("NOTHING ARRIVED. Either the integration is off in BetterDisplay")
    print("(Settings -> Application -> Integration -> OSD notification, 4.2.1+),")
    print("or it stopped publishing. Crema draws its brightness HUD from exactly")
    print("this payload, so with nothing arriving there is nothing for it to draw.")
} else {
    print("The channel is alive, so a missing bar is Crema's side, not the neighbour's.")
}
