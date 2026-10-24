// Can Crema hand BetterDisplay's own OSD off and back over the request channel?
//
// The BetterDisplay Guide ("Third-party app integration", section "Coordinate
// feedback settings through requests", read 2026-10-18) tells a receiving app to
// read and save `osdShowBasic`, `osdShowCustom` and `osdIntegrationNotification`,
// turn off the overlays it replaces, and restore the saved values on shutdown,
// saying "the same parameters work in DNC requests and can be read again". It
// documents the CLI form only, and says nothing about whether a `set` persists.
// This probe measures the three things the design rests on:
//
//   1. the `get` shape over the notification channel, and what the payload is;
//   2. that a `set` lands and reads back (`--write` only);
//   3. whether the `set` is written to BetterDisplay's preferences, which
//      decides whether a crash of the receiver leaves the user's OSD off.
//
// `proAvailable` goes first as the shape control the Guide names: it answers
// whatever the licence, so silence there means the request path itself is wrong.
//
// Measured with this probe 2026-10-18, BetterDisplay 5.1.1: every `get` answered
// `result=true` with `on` or `off` in 1–7 ms; `set osdShowBasic=off` answered
// `result=true` with no payload, read back `off`, and turned `osdShowBasic` from 1
// to 0 in BetterDisplay's preferences on disk; the restore put it back. The one
// `get` of all three switches answered `on,on,on`, in an order nothing documents,
// which is why the app asks one switch per request. A run where a `set` leaves the
// preferences untouched invalidates the crash-recovery premise in
// docs/DECISIONS.md: the-neighbour-indicator-is-borrowed.
//
// Run:  swift scripts/probes/osd-settings-betterdisplay.swift          (read only)
//       swift scripts/probes/osd-settings-betterdisplay.swift --write  (flips
//       osdShowBasic, reads it back, restores it, reads it again)

import AppKit
import Foundation

let requestName = Notification.Name("pro.betterdisplay.BetterDisplay.request")
let responseName = Notification.Name("pro.betterdisplay.BetterDisplay.response")
let domain = "pro.betterdisplay.BetterDisplay"
let settings = ["proAvailable", "osdShowBasic", "osdShowCustom", "osdIntegrationNotification"]
let writes = CommandLine.arguments.contains("--write")

final class Answers: @unchecked Sendable {
    private let lock = NSLock()
    private var byUUID: [String: (result: Bool?, payload: String?, at: Date)] = [:]
    func store(_ uuid: String, _ result: Bool?, _ payload: String?) {
        lock.withLock { byUUID[uuid] = (result, payload, Date()) }
    }

    func take(_ uuid: String) -> (result: Bool?, payload: String?, at: Date)? {
        lock.withLock { byUUID[uuid] }
    }
}

let answers = Answers()

DistributedNotificationCenter.default().addObserver(
    forName: responseName, object: nil, queue: .main
) { note in
    guard let json = note.object as? String,
          let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let uuid = obj["uuid"] as? String
    else { return }
    answers.store(uuid, obj["result"] as? Bool, obj["payload"].map { "\($0)" })
}

/// Posts one request and waits up to `timeout` for its answer, printing the
/// round-trip so the channel's unmeasured deadline gets a number beside it.
@discardableResult
func ask(_ commands: [String], _ parameters: [String: String], timeout: TimeInterval = 3) -> (Bool?, String?)? {
    let uuid = UUID().uuidString
    let body: [String: Any] = ["uuid": uuid, "commands": commands, "parameters": parameters]
    guard let data = try? JSONSerialization.data(withJSONObject: body),
          let json = String(data: data, encoding: .utf8) else { return nil }
    let sent = Date()
    DistributedNotificationCenter.default().postNotificationName(
        requestName, object: json, userInfo: nil, deliverImmediately: true
    )
    let deadline = sent.addingTimeInterval(timeout)
    while Date() < deadline, answers.take(uuid) == nil {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    let label = "\(commands.joined(separator: "+")) \(parameters.map { $0.value.isEmpty ? $0.key : "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))"
    guard let answer = answers.take(uuid) else {
        print("  \(label.padding(toLength: 44, withPad: " ", startingAt: 0)) -> NO ANSWER in \(timeout)s")
        return nil
    }
    let ms = Int(answer.at.timeIntervalSince(sent) * 1000)
    print("  \(label.padding(toLength: 44, withPad: " ", startingAt: 0)) -> result=\(answer.result.map(String.init) ?? "nil")  payload=\(answer.payload ?? "nil")  (\(ms) ms)")
    return (answer.result, answer.payload)
}

/// BetterDisplay's own preferences, read through `defaults` so the reading is
/// what is on disk (and in cfprefsd), not what this process cached.
func storedOSDKeys() -> [String: String] {
    let pipe = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["read", domain]
    process.standardOutput = pipe
    process.standardError = Pipe()
    try? process.run()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    var keys: [String: String] = [:]
    for line in out.split(separator: "\n") where line.lowercased().contains("osd") {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { continue }
        keys[parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "\""))] =
            parts[1].trimmingCharacters(in: CharacterSet(charactersIn: ";"))
    }
    return keys
}

func printDiff(_ before: [String: String], _ after: [String: String]) {
    let changed = Set(before.keys).union(after.keys).sorted().filter { before[$0] != after[$0] }
    if changed.isEmpty { print("  no OSD key changed in \(domain)") }
    for key in changed { print("  \(key): \(before[key] ?? "absent") -> \(after[key] ?? "absent")") }
}

let running = NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == domain }
print("BetterDisplay running: \(running != nil)  version: \(running?.bundleURL.flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "?")")

print("\n1. one `get` per setting:")
var current: [String: String] = [:]
for setting in settings {
    if let (result, payload) = ask(["get"], [setting: ""]), result == true, let payload { current[setting] = payload }
}

print("\n2. the three OSD settings in one `get`, as the Guide's CLI line asks them:")
ask(["get"], ["osdShowBasic": "", "osdShowCustom": "", "osdIntegrationNotification": ""])

print("\nstored OSD keys in \(domain):")
let stored = storedOSDKeys()
for key in stored.keys.sorted() { print("  \(key) = \(stored[key]!)") }

guard writes else {
    print("\nread only. Run with --write to flip osdShowBasic and restore it.")
    exit(0)
}

guard let original = current["osdShowBasic"], original == "on" || original == "off" else {
    print("\nosdShowBasic did not read as on/off, so there is nothing safe to restore: not writing.")
    exit(1)
}

let flipped = original == "on" ? "off" : "on"

print("\n3. set osdShowBasic=\(flipped), read it back:")
ask(["set"], ["osdShowBasic": flipped])
ask(["get"], ["osdShowBasic": ""])
RunLoop.main.run(until: Date().addingTimeInterval(1))
print("stored keys after the set:")
let afterSet = storedOSDKeys()
printDiff(stored, afterSet)

print("\n4. restore osdShowBasic=\(original), read it back:")
ask(["set"], ["osdShowBasic": original])
ask(["get"], ["osdShowBasic": ""])
RunLoop.main.run(until: Date().addingTimeInterval(1))
print("stored keys after the restore:")
printDiff(stored, storedOSDKeys())
