// Hardware probes left open by the 2026-07-29 audit, in one run.
//
// Each one decides whether a specific fix is mandatory or merely defensive, and
// none of them can be answered from a header or a unit test. Read-only except
// probe 2, which writes the keyboard backlight and puts it back.
//
// Run:  swift scripts/probes/hardware-probes.swift
//
// Probe 2 hammers an undocumented Apple client from three threads on purpose. If
// this process crashes inside CoreBrightness, that IS the result — it means the
// bridge must serialize, and the crash happened here instead of in the app.

import AppKit
import CoreGraphics
import Foundation

func header(_ n: Int, _ title: String) {
    print("\n=== PROBE \(n): \(title)")
}

// MARK: - 1. Display identity: does the built-in resolution hold in clamshell?

header(1, "display identity (decides: brightness in clamshell / external-as-main)")

func activeDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &n) == .success, n > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    guard CGGetActiveDisplayList(n, &ids, &n) == .success else { return [] }
    return Array(ids.prefix(Int(n)))
}

let dsHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
typealias DSGet = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
let dsGet = dlsym(dsHandle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: DSGet.self) }

let main = CGMainDisplayID()
let builtIn = activeDisplays().first { CGDisplayIsBuiltin($0) != 0 }
print("  CGMainDisplayID()   = \(main)")
print("  built-in resolved   = \(builtIn.map(String.init) ?? "nil  <- clamshell: brightness degrades, as designed")")
for id in activeDisplays() {
    var v: Float = 0
    let rc = dsGet?(id, &v) ?? -1
    let tag = rc == 0 ? "ok val=\(String(format: "%.3f", v))" : "FAILS (rc=\(rc))"
    print("    display \(id): builtin=\(CGDisplayIsBuiltin(id) != 0) main=\(id == main) DisplayServices \(tag)")
}

print("  WHAT TO LOOK FOR: with the menu bar dragged to the external monitor, the")
print("  built-in must still resolve and still be the only one that answers rc=0.")

// MARK: - 2. Is the private keyboard client thread-safe?

header(2, "KeyboardBrightnessClient under concurrent use (decides: must the bridge serialize?)")

let cbHandle = dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)
if cbHandle == nil {
    print("  CoreBrightness did not load — probe skipped (the app degrades here too).")
} else if let clientClass = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type {
    let client = clientClass.init()
    let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
    let builtInSel = NSSelectorFromString("isKeyboardBuiltIn:")
    let getSel = NSSelectorFromString("brightnessForKeyboard:")
    let setSel = NSSelectorFromString("setBrightness:forKeyboard:")

    guard client.responds(to: idsSel),
          let rawIDs = client.perform(idsSel)?.takeUnretainedValue() as? [NSNumber] else {
        print("  copyKeyboardBacklightIDs answered nothing — no built-in backlight on this Mac.")
        exit(0)
    }
    // isKeyboardBuiltIn: returns a BOOL, so it needs an IMP cast for the same
    // reason the accessors below do — `perform` would answer a garbage object.
    typealias BuiltInIMP = @convention(c) (AnyObject, Selector, NSNumber) -> ObjCBool
    let builtInIMP = client.method(for: builtInSel).map { unsafeBitCast($0, to: BuiltInIMP.self) }
    let keyboardID = rawIDs.first { id in
        guard let builtInIMP else { return true }
        return builtInIMP(client, builtInSel, id).boolValue
    } ?? rawIDs.first

    guard let keyboardID else {
        print("  no keyboard ID enumerated — nothing to hammer.")
        exit(0)
    }
    print("  enumerated IDs: \(rawIDs.map(\.uint64Value)) — using \(keyboardID.uint64Value)")

    // Both accessors go through an IMP cast, never `perform`: these return and
    // take a FLOAT, and `perform` can only pass and answer objects — it hands back
    // nil for the getter, which silently turns the read leg of this probe into 400
    // no-ops that report "no anomalies".
    typealias GetIMP = @convention(c) (AnyObject, Selector, NSNumber) -> Float
    typealias SetIMP = @convention(c) (AnyObject, Selector, Float, NSNumber) -> Void
    guard let getIMP = client.method(for: getSel).map({ unsafeBitCast($0, to: GetIMP.self) }),
          let setIMP = client.method(for: setSel).map({ unsafeBitCast($0, to: SetIMP.self) }) else {
        print("  brightnessForKeyboard:/setBrightness:forKeyboard: did not resolve — probe skipped.")
        exit(0)
    }

    // Remember the level so the probe leaves the machine as it found it.
    let original = getIMP(client, getSel, keyboardID)
    print("  level before: \(String(format: "%.3f", original))")

    let lock = NSLock()
    var readings: [Float] = []
    var anomalies: [String] = []
    let group = DispatchGroup()

    for worker in 0..<3 {
        DispatchQueue.global().async(group: group) {
            for i in 0..<400 {
                switch worker {
                case 0:
                    let v = getIMP(client, getSel, keyboardID)
                    lock.withLock {
                        readings.append(v)
                        if !v.isFinite || v < 0 || v > 1 { anomalies.append("out-of-range read \(v)") }
                    }
                case 1:
                    setIMP(client, setSel, Float(i % 2 == 0 ? 0.4 : 0.6), keyboardID)
                default:
                    _ = client.perform(idsSel)?.takeUnretainedValue()
                }
            }
        }
    }
    let finished = group.wait(timeout: .now() + 90)
    // Only restore a real level. The getter answers -1 when it cannot read, and
    // writing that back would hand the backlight a value that is not a brightness.
    if original >= 0, original <= 1 {
        setIMP(client, setSel, original, keyboardID)
    } else {
        print("  (level not restored: it never read as a level)")
    }
    print("  finished: \(finished == .success ? "yes" : "TIMED OUT after 90 s <- a call hung, which is itself the answer")")
    let distinct = Set(readings.map { String(format: "%.3f", $0) })
    let cannotRead = !readings.isEmpty && readings.allSatisfy { $0 < 0 }
    print("  reads: \(readings.count)   distinct values: \(distinct.count)")
    if cannotRead {
        print("  every read answered -1: THIS PROCESS cannot read the backlight (the app,")
        print("  with its own client and run loop, does). So the read leg is unanswered here")
        print("  — what this run still proves is crash-safety: 400 concurrent writes and 400")
        print("  enumerations against one client, no crash and no hang.")
    } else {
        print("  anomalies: \(anomalies.isEmpty ? "none" : anomalies.prefix(5).joined(separator: ", "))")
        print("  WHAT TO LOOK FOR: a torn value — a read outside 0...1, or a value that is")
        print("  neither what was written nor what was there — makes serializing the bridge")
        print("  mandatory. No crash, no hang and no torn read keeps the fix defensive.")
    }
} else {
    print("  KeyboardBrightnessClient did not resolve — probe skipped.")
}

// MARK: - 3. Can two screens ever share one display UUID?

header(3, "display UUID collisions (decides: was the hotplug crash reachable?)")

var seen: [String: [String]] = [:]
for screen in NSScreen.screens {
    let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    let id = CGDirectDisplayID(number?.uint32Value ?? 0)
    let uuid = CGDisplayCreateUUIDFromDisplayID(id)
        .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "nil"
    let label = "\(screen.localizedName) [id \(id), builtin=\(CGDisplayIsBuiltin(id) != 0), mirrored=\(CGDisplayIsInMirrorSet(id) != 0)]"
    seen[uuid, default: []].append(label)
    print("  \(uuid)  <-  \(label)")
}

let collisions = seen.filter { $0.value.count > 1 }
print("  collisions: \(collisions.isEmpty ? "none in THIS arrangement" : "\(collisions.count) <- the crash was reachable")")
print("  WHAT TO LOOK FOR: repeat with mirroring ON, with two identical monitors,")
print("  and with Sidecar or AirPlay active. One collision anywhere means the")
print("  Dictionary trap this round removed was a live crash, not a net.")

// MARK: - 4. Who is actually in the media-key tap chain?

header(4, "event-tap chain (decides: can the menu accuse a neighbour unfairly?)")
print("  NOTE: reading this list resets every tap's min/max latency counters,")
print("  system-wide. That is why the app reads it only when the menu opens.")

var tapCount: UInt32 = 0
if CGGetEventTapList(0, nil, &tapCount) == .success, tapCount > 0 {
    var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(tapCount))
    if CGGetEventTapList(tapCount, &taps, &tapCount) == .success {
        let nxSysDefined: UInt64 = 1 << 14
        for (index, tap) in taps.prefix(Int(tapCount)).enumerated() {
            let place: String
            switch tap.tapPoint {
            case .cghidEventTap: place = "HID       "
            case .cgSessionEventTap: place = "session   "
            case .cgAnnotatedSessionEventTap: place = "annotated "
            @unknown default: place = "unknown   "
            }
            let app = NSRunningApplication(processIdentifier: pid_t(tap.tappingProcess))
            let name = app?.bundleIdentifier ?? "pid \(tap.tappingProcess)"
            let mediaKeys = (tap.eventsOfInterest & nxSysDefined) != 0
            let perProcess = tap.processBeingTapped != 0 ? " targets pid \(tap.processBeingTapped)" : ""
            print("  [\(index)] \(place) \(tap.enabled ? "enabled " : "DISABLED") \(tap.options == .defaultTap ? "filter" : "listen") \(mediaKeys ? "NX_SYSDEFINED" : "             ") \(name)\(perProcess)")
        }
    }
} else {
    print("  CGGetEventTapList answered nothing.")
}

print("  WHAT TO LOOK FOR: any tap at the ANNOTATED point, or any with a non-zero")
print("  processBeingTapped that is not Crema. Either can be listed ahead of us")
print("  while being structurally incapable of stealing our keys — which is the")
print("  false accusation the menu could print today.")

print("\n=== done")
