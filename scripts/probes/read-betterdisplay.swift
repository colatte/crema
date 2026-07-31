// Can we READ a display's brightness from BetterDisplay?
//
// This gates the whole "keys follow the screen you are using" design. The
// suppressor's cycle is read -> step -> write -> read back, and the channel built
// so far only writes. Without a read there is no `before` to step from, and the
// design has to change shape entirely.
//
// Sends `get` over the same request/response channel the app uses — same uuid
// pairing, same JSON-in-`object` convention — and prints whatever comes back, for
// several identifier spellings, because the one BetterDisplay accepts is not
// documented anywhere we have.
//
// Run:  swift scripts/probes/read-betterdisplay.swift <displayID>
//       e.g. swift scripts/probes/read-betterdisplay.swift 2

import AppKit
import Foundation

let displayID = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "2"
let requestName = Notification.Name("pro.betterdisplay.BetterDisplay.request")
let responseName = Notification.Name("pro.betterdisplay.BetterDisplay.response")

// Every identifier worth trying in one run: the auto-selecting one the write path
// uses, the three OSD flavours, and the raw DDC name.
// Split in two on purpose. The metadata ones are the SHAPE test: BetterDisplay
// certainly knows a display's name and UUID, so if none of those answer, the
// request itself is wrong and nothing about brightness has been learned. Only with
// the shape proven does a refused brightness read mean brightness is not gettable.
let metadataIdentifiers = ["UUID", "name", "serial", "vendor", "model", "productName"]
let brightnessIdentifiers = [
    "brightness",
    "combinedBrightness",
    "hardwareBrightness",
    "softwareBrightness",
    "ddcBrightness",
]
let identifiers = metadataIdentifiers + brightnessIdentifiers

var answers: [String: String] = [:]
var pending: [String: String] = [:]   // uuid -> identifier
let lock = NSLock()

DistributedNotificationCenter.default().addObserver(
    forName: responseName, object: nil, queue: .main
) { note in
    guard let json = note.object as? String,
          let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let uuid = obj["uuid"] as? String
    else { return }
    let identifier = lock.withLock { pending[uuid] } ?? "?"
    let result = obj["result"] as? Bool
    let payload = obj["payload"]
    lock.withLock {
        answers[identifier] = "result=\(result.map(String.init) ?? "nil")  payload=\(payload.map { "\($0)" } ?? "nil")"
    }
    print("  \(identifier.padding(toLength: 20, withPad: " ", startingAt: 0)) -> result=\(result.map(String.init) ?? "nil")  payload=\(payload.map { "\($0)" } ?? "nil")")
}

let running = NSWorkspace.shared.runningApplications
    .contains { $0.bundleIdentifier == "pro.betterdisplay.BetterDisplay" }
print("BetterDisplay running: \(running)")
print("asking display \(displayID) for its brightness, \(identifiers.count) spellings:\n")

for identifier in identifiers {
    let uuid = UUID().uuidString
    lock.withLock { pending[uuid] = identifier }
    let body: [String: Any] = [
        "uuid": uuid,
        "commands": ["get"],
        "parameters": ["displayID": displayID, "identifier": identifier],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: body),
          let json = String(data: data, encoding: .utf8) else { continue }
    DistributedNotificationCenter.default().postNotificationName(
        requestName, object: json, userInfo: nil, deliverImmediately: true
    )
}

let deadline = Date().addingTimeInterval(8)
while Date() < deadline { RunLoop.main.run(mode: .default, before: deadline) }

print("\n=== \(answers.count) of \(identifiers.count) answered")
func worked(_ identifier: String) -> Bool {
    guard let a = answers[identifier] else { return false }
    return a.contains("result=true") && !a.contains("payload=nil")
}

let shapeProven = metadataIdentifiers.contains(where: worked)
let brightnessReadable = brightnessIdentifiers.filter(worked)

print("request shape proven by metadata: \(shapeProven)")
if !shapeProven {
    print("NOTHING answered usefully, INCLUDING metadata — so this request shape is")
    print("wrong and nothing has been learned about reading brightness. Do not")
    print("conclude from this run.")
} else if brightnessReadable.isEmpty {
    print("Shape is right and brightness is NOT gettable. The read-step-write-verify")
    print("cycle cannot run against an external display, so keys-follow-the-screen")
    print("needs a different shape: seed the level from the neighbour's own OSD")
    print("report, or let the first press through and step from what it reports back.")
} else {
    print("BRIGHTNESS READABLE via: \(brightnessReadable.joined(separator: ", "))")
    print("The cycle can read the external's level and the design holds as drawn.")
}
