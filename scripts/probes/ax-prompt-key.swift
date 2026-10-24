// Decides: which string the SDK's `kAXTrustedCheckOptionPrompt` holds, the key
// `AXAccessibilityPermission.requestAccess()` writes as a literal because Swift 6
// rejects any reference to that C global (it carries no concurrency annotation).
// Apple's reference page names the symbol and documents no value, so the literal
// rests on this reading.
//
// CONTROL that makes the comparison mean something: it also prints the symbol's
// CFString length, so an empty or unexpected value is visible as such rather
// than read as a match.
//
// Measured with this probe 2026-10-15, macOS 27.0.1 (26A434), arm64, Swift 6.4
// on the macOS 27.0 SDK: `AXTrustedCheckOptionPrompt`, length 26, matches: true.
// Invalidated by a run that prints another value or `matches: false`.
//
// Read-only: it reads one constant and never calls AXIsProcessTrustedWithOptions,
// so no prompt appears and no privacy setting changes.
//
// Run: swift -swift-version 5 scripts/probes/ax-prompt-key.swift
import ApplicationServices
import Foundation

let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
print("kAXTrustedCheckOptionPrompt: \(key), length \(key.count)")
print("matches: \(key == "AXTrustedCheckOptionPrompt")")
print(ProcessInfo.processInfo.operatingSystemVersionString)
