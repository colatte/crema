// Decides: whether EphemeralDefaults' deinit must unlink the suite's plist
// itself, or whether removePersistentDomain(forName:) already deletes the file.
//
// Apple documents the method over keys and values only ("Removes the keys and
// values from the specified persistent domain") — the file's fate is
// unspecified. Measured 2026-08-08:
//   A  the file SURVIVES the call — in the field the survivors are 42-byte
//      plists, the emptied domain flushed to disk as an empty binary plist.
//      A doubles as the control: a file that never existed would prove
//      nothing about deletion.
//   B  an unlink right after the call reads absent 3 s later.
//   C  synchronize() between remove and unlink is not merely useless, it is
//      a provocation: it schedules a flush of the emptied domain that races
//      the unlink, and the empty file can come back within the window
//      (measured both ways on consecutive runs — racy).
//   D  B reads absent across process death too — the sequence runs in a
//      child that exits immediately, checked from outside 4 s later.
//
// THE WINDOWS ABOVE ARE TOO SHORT TO PROVE PERMANENCE. Measured right after
// two probe runs: six empty plists back on disk, B's and D's among them, two
// with mtimes 2-7 MINUTES past the death of every probe process — cfprefsd
// re-materializes an emptied domain's file at its own pace, client dead or
// not. Absence inside this probe's windows is evidence the unlink helps, not
// that it suffices: that is why EphemeralDefaults pairs the deinit unlink
// with a reap of past runs' CremaTests.* files at next-process start.
//
// Run:  swift scripts/probes/remove-persistent-domain.swift
// Writes only probe-named domains and cleans up after itself — subject to the
// same late reflush it documents, so finding its own residue afterwards IS
// the measured behaviour, not a cleanup bug.

import Foundation

let prefsDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Preferences")

func plistURL(_ name: String) -> URL { prefsDir.appendingPathComponent(name + ".plist") }

func report(_ name: String) -> String {
    let url = plistURL(name)
    guard FileManager.default.fileExists(atPath: url.path) else { return "absent" }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    return "present (\(size.map(String.init) ?? "?") bytes)"
}

func makeSuite(_ label: String) -> (name: String, defaults: UserDefaults) {
    let name = "CremaTests.PROBE-\(label)-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("UserDefaults refused suite \(name)")
    }
    return (name, defaults)
}

// Child mode (probe D): the B sequence, then immediate exit — the reflush, if
// one were coming, would have to chase a dead client.
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "child" {
    let name = CommandLine.arguments[2]
    guard let defaults = UserDefaults(suiteName: name) else {
        fatalError("UserDefaults refused suite \(name)")
    }
    defaults.set(true, forKey: "k")
    Thread.sleep(forTimeInterval: 1.0)
    defaults.removePersistentDomain(forName: name)
    try? FileManager.default.removeItem(at: plistURL(name))
    exit(0)
}

// A — what the deinit did before the fix: write, removePersistentDomain, stop.
let suiteA = makeSuite("A")
suiteA.defaults.set(true, forKey: "k")
Thread.sleep(forTimeInterval: 1.0)
print("A control, after set:", report(suiteA.name))
suiteA.defaults.removePersistentDomain(forName: suiteA.name)
Thread.sleep(forTimeInterval: 3.0)
print("A after removePersistentDomain + 3 s:", report(suiteA.name))

// B — the fix: removePersistentDomain, then unlink the file immediately.
let suiteB = makeSuite("B")
suiteB.defaults.set(true, forKey: "k")
Thread.sleep(forTimeInterval: 1.0)
suiteB.defaults.removePersistentDomain(forName: suiteB.name)
try? FileManager.default.removeItem(at: plistURL(suiteB.name))
Thread.sleep(forTimeInterval: 3.0)
print("B remove + immediate unlink + 3 s:", report(suiteB.name))

// C — the trap: forcing the flush (synchronize) between remove and unlink.
let suiteC = makeSuite("C")
suiteC.defaults.set(true, forKey: "k")
Thread.sleep(forTimeInterval: 1.0)
suiteC.defaults.removePersistentDomain(forName: suiteC.name)
suiteC.defaults.synchronize()
try? FileManager.default.removeItem(at: plistURL(suiteC.name))
Thread.sleep(forTimeInterval: 3.0)
print("C remove + synchronize + unlink + 3 s:", report(suiteC.name), "— racy: either answer can land")

// D — B across process death, checked from outside the dead process.
let dName = "CremaTests.PROBE-D-\(UUID().uuidString)"
let child = Process()
child.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
child.arguments = [URL(fileURLWithPath: CommandLine.arguments[0]).path, "child", dName]
try child.run()
child.waitUntilExit()
Thread.sleep(forTimeInterval: 4.0)
print("D child ran B and died; 4 s later:", report(dName))

for name in [suiteA.name, suiteB.name, suiteC.name, dName] { try? FileManager.default.removeItem(at: plistURL(name)) }
