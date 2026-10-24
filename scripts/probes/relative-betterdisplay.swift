// Does BetterDisplay accept a RELATIVE brightness change?
//
// A relative write — "one step up" — needs no `before`, so it would let the keys
// step a display without reading its CURRENT level. This probe tries verbs
// (`increment`, `up`, ...) and a sign on the value. Neither is BetterDisplay's
// shape, so a refusal here is not a limitation: the relative write is the
// documented `offset` parameter (`"brightness":"-5%","offset":""` with `set`;
// source: BetterDisplay wiki, "Integration features, CLI", a page the vendor marks
// legacy, read Oct 2026),
// and a signed value is read as an ABSOLUTE — `+0.0625` sets the monitor to 6.3%
// and looks accepted as a delta. Nor is the level unreadable: `get` refuses
// brightness only through the `identifier` metadata door, and answers when the
// feature is asked by its own key (docs/DECISIONS.md:
// neighbour-features-are-not-identifiers).
//
// Sends each candidate shape and prints what comes back. `result=true` alone is
// not the finding; watch the monitor to confirm it MOVED, and by how much — a
// neighbour that accepts a command it does not honour, or honours it as something
// else, is the worst outcome to build on. The "impasse stands" verdict this probe
// prints covers these shapes only.
//
// Run:  swift scripts/probes/relative-betterdisplay.swift <displayID>
//       e.g. swift scripts/probes/relative-betterdisplay.swift 2

import AppKit
import Foundation

let displayID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "2"
let requestName = Notification.Name("pro.betterdisplay.BetterDisplay.request")
let responseName = Notification.Name("pro.betterdisplay.BetterDisplay.response")

/// Each candidate is (label, commands, parameters). The absolute set is included
/// as the CONTROL: it is known to work, so if it fails here the probe itself is
/// wrong and nothing else in the run means anything.
let candidates: [(String, [String], [String: String])] = [
    ("CONTROL absolute set", ["set"], ["displayID": displayID, "brightness": "0.5"]),
    ("increment +0.0625", ["increment"], ["displayID": displayID, "brightness": "0.0625"]),
    ("decrement 0.0625", ["decrement"], ["displayID": displayID, "brightness": "0.0625"]),
    ("set brightness=+0.0625", ["set"], ["displayID": displayID, "brightness": "+0.0625"]),
    ("set brightness=-0.0625", ["set"], ["displayID": displayID, "brightness": "-0.0625"]),
    ("set relative=true", ["set"], ["displayID": displayID, "brightness": "0.0625", "relative": "true"]),
    ("up", ["up"], ["displayID": displayID, "brightness": "0.0625"]),
    ("down", ["down"], ["displayID": displayID, "brightness": "0.0625"]),
    ("increase", ["increase"], ["displayID": displayID, "brightness": "0.0625"]),
    ("decrease", ["decrease"], ["displayID": displayID, "brightness": "0.0625"]),
]

var pending: [String: String] = [:]
var answered: [String: Bool] = [:]
let lock = NSLock()

DistributedNotificationCenter.default().addObserver(
    forName: responseName, object: nil, queue: .main
) { note in
    guard let json = note.object as? String,
          let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let uuid = obj["uuid"] as? String else { return }
    let label = lock.withLock { pending[uuid] } ?? "?"
    let ok = (obj["result"] as? Bool) ?? false
    lock.withLock { answered[label] = ok }
    let payload = obj["payload"].map { " payload=\($0)" } ?? ""
    print("  \(label.padding(toLength: 26, withPad: " ", startingAt: 0)) result=\(ok)\(payload)")
}

// Also listen to the OSD channel: if a relative command makes the neighbour
// PUBLISH, that is the verification path the apply-verify cycle would need, and
// its absence is what an absolute `set` already showed (it does not echo).
var reports = 0
DistributedNotificationCenter.default().addObserver(
    forName: Notification.Name("pro.betterdisplay.BetterDisplay.osd"), object: nil, queue: .main
) { _ in
    lock.withLock { reports += 1 }
}

print("asking display \(displayID), one shape per second — WATCH THE MONITOR\n")
var delay = 0.0
for (label, commands, parameters) in candidates {
    let uuid = UUID().uuidString
    lock.withLock { pending[uuid] = label }
    var body: [String: Any] = ["uuid": uuid, "commands": commands]
    body["parameters"] = parameters
    guard let data = try? JSONSerialization.data(withJSONObject: body),
          let json = String(data: data, encoding: .utf8) else { continue }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        print("-> \(label)")
        DistributedNotificationCenter.default().postNotificationName(
            requestName, object: json, userInfo: nil, deliverImmediately: true
        )
    }
    delay += 1.0
}

let deadline = Date().addingTimeInterval(delay + 3)
while Date() < deadline { RunLoop.main.run(mode: .default, before: deadline) }

let accepted = answered.filter(\.value).keys.filter { $0 != "CONTROL absolute set" }.sorted()
print("\n=== control (absolute set) answered: \(answered["CONTROL absolute set"].map(String.init) ?? "NO ANSWER")")
print("=== OSD notifications during the run: \(reports)")
if answered["CONTROL absolute set"] != true {
    print("The control failed, so this probe proves nothing — fix it before reading the rest.")
} else if accepted.isEmpty {
    print("None of THESE relative shapes was accepted. That covers only the shapes")
    print("asked: the relative write is the documented `offset` parameter, and the")
    print("level is readable by feature key (read-betterdisplay.swift).")
} else {
    print("ACCEPTED: \(accepted.joined(separator: ", "))")
    print("If the monitor also MOVED for one of these, the keys can follow the screen")
    print("you are on without ever reading a level.")
}
