// Does BetterDisplay accept a RELATIVE brightness change?
//
// This is the one thing that would dissolve the impasse. The keys cannot follow
// the screen you are looking at because stepping needs the display's CURRENT
// level, and the neighbour's `get` refuses every spelling of brightness (measured:
// docs/DECISIONS.md: external-brightness-is-write-only). But that only binds an
// ABSOLUTE write. A relative one — "one step up" — needs no `before` at all, and
// the whole read requirement disappears.
//
// Sends each candidate shape and prints what comes back. `result=true` on any of
// them is the finding; watch the monitor to confirm it also MOVED, because a
// neighbour that accepts a command it does not honour would be the worst outcome
// to build on.
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
    print("No relative shape accepted. Stepping an external display needs its current")
    print("level, the neighbour will not give it, and the impasse stands.")
} else {
    print("ACCEPTED: \(accepted.joined(separator: ", "))")
    print("If the monitor also MOVED for one of these, the keys can follow the screen")
    print("you are on without ever reading a level.")
}
