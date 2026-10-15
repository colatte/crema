// Can we READ a display's brightness from BetterDisplay?
//
// This gates the whole "keys follow the screen you are using" design. The
// suppressor's cycle is read -> step -> write -> read back; without a read there
// is no `before` to step from.
//
// Sends `get` over the same request/response channel the app uses — same uuid
// pairing, same JSON-in-`object` convention — through BOTH doors, and prints what
// comes back. Passed as `identifier`, a spelling goes through BetterDisplay's
// METADATA door, which answers name, UUID and the like and refuses every
// brightness spelling. Asked by its own name as the parameter KEY with no value
// (`"brightness":""`), a feature answers (docs/DECISIONS.md:
// neighbour-features-are-not-identifiers). The verdict reads the feature key only;
// the metadata door is printed so a refusal there is never mistaken for one.
// Measured with this probe 2026-10-14, BetterDisplay 5.1.1, built-in display
// (displayID 1): every metadata spelling answered, every brightness spelling
// through `identifier` refused; by feature key `brightness` 0.671,
// `combinedBrightness` 0.671, `hardwareBrightness` 0.561, `softwareBrightness`
// 1.0, and `ddcBrightness` refused (a built-in panel has no DDC).
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
// request itself is wrong and nothing about brightness has been learned. With the
// shape proven, a refused brightness read means only that the metadata door does
// not carry brightness; the feature key does (header above).
let metadataIdentifiers = ["UUID", "name", "serial", "vendor", "model", "productName"]
let brightnessIdentifiers = [
    "brightness",
    "combinedBrightness",
    "hardwareBrightness",
    "softwareBrightness",
    "ddcBrightness",
]
let identifiers = metadataIdentifiers + brightnessIdentifiers
/// The label a feature-key ask is recorded under, apart from its metadata twin.
func featureKey(_ name: String) -> String { "key:" + name }

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
let asks: [(label: String, parameters: [String: String])] =
    identifiers.map { ($0, ["displayID": displayID, "identifier": $0]) }
        + brightnessIdentifiers.map { (featureKey($0), ["displayID": displayID, $0: ""]) }
print("asking display \(displayID) for its brightness, \(asks.count) asks through both doors:\n")

for ask in asks {
    let uuid = UUID().uuidString
    lock.withLock { pending[uuid] = ask.label }
    let body: [String: Any] = [
        "uuid": uuid,
        "commands": ["get"],
        "parameters": ask.parameters,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: body),
          let json = String(data: data, encoding: .utf8) else { continue }
    DistributedNotificationCenter.default().postNotificationName(
        requestName, object: json, userInfo: nil, deliverImmediately: true
    )
}

let deadline = Date().addingTimeInterval(8)
while Date() < deadline { RunLoop.main.run(mode: .default, before: deadline) }

print("\n=== \(answers.count) of \(asks.count) answered")
func worked(_ identifier: String) -> Bool {
    guard let a = answers[identifier] else { return false }
    return a.contains("result=true") && !a.contains("payload=nil")
}

let shapeProven = metadataIdentifiers.contains(where: worked)
let brightnessReadable = brightnessIdentifiers.filter { worked(featureKey($0)) }
let metadataDoorRefused = brightnessIdentifiers.allSatisfy { !worked($0) }

print("request shape proven by metadata: \(shapeProven)")
if !shapeProven {
    print("NOTHING answered usefully, INCLUDING metadata — so this request shape is")
    print("wrong and nothing has been learned about reading brightness. Do not")
    print("conclude from this run.")
} else if brightnessReadable.isEmpty {
    print("Shape is right and NO feature key answered for this display: either it")
    print("has no brightness BetterDisplay controls, or the feature vocabulary moved.")
    print("Check the display ID and BetterDisplay's integration docs before concluding.")
} else {
    print("BRIGHTNESS READABLE via the feature key: \(brightnessReadable.joined(separator: ", "))")
    print("The read-step-write-verify cycle has its `before` on this display.")
}

print("metadata door refused every brightness spelling: \(metadataDoorRefused) (expected; not a limitation)")
