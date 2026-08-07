// Can a window of ours composite over the lock shield after all?
//
// Decides whether docs/LOCKSCREEN-INVESTIGATION.md's NO-GO still stands. That
// investigation swept NSWindow.level across five values — mainMenu+3,
// screenSaver, assistiveTechHigh, CGShieldingWindowLevel() and
// kCGMaximumWindowLevel — and none composited. The conclusion drawn was "no
// window path exists". This probe exists because that may be the wrong axis:
//
//   window LEVEL orders windows WITHIN a space.
//   the lock shield is a SPACE, at absolute level 300.
//
// No window level can lift a window out of the space it lives in, so a sweep
// that holds the space at the default (absolute level 0) and varies only the
// level cannot distinguish "impossible" from "wrong knob". SkyLight exposes the
// other knob: create a space, set its ABSOLUTE level above the shield's, and
// move the window into it. The ladder, from SkyLightWindow (MIT):
//
//   0   default            300  screen lock          500  boot progress
//   100 setup assistant    400  notification centre  600  VoiceOver
//   200 security agent          AT screen lock
//
// RESULT, 2026-08-07 (macOS 26, Apple Silicon, run by the author): only RAISED
// survived the lock. The control vanished beside it — same machine, same moment,
// one variable. The NO-GO was over-generalised; the space is the knob. Kept
// runnable because the path is private and a macOS update can retire it: if this
// ever starts printing a missing symbol, or both markers go, that is the notice.
//
// Run:  swift scripts/probes/lockscreen-space.swift
// Then: lock the screen (Control-Command-Q) and look. Unlock to end it.
//
// THE CONTROL, which is what makes a negative result mean anything: the probe
// draws TWO markers. One is moved into the raised space; the other is an
// ordinary window at kCGMaximumWindowLevel — the best of the five the original
// investigation tried. Before locking, both must be visible, or the probe
// itself is broken and neither result counts. After locking:
//
//   both gone      -> the NO-GO holds; the axis was not the problem.
//   only RAISED    -> the NO-GO was over-generalised; the space is the knob.
//   only CONTROL   -> something is very wrong; report it, do not build on it.
//
// Read-only with respect to the app: touches no preference, no display, no key.

import AppKit

// MARK: - SkyLight, resolved at runtime like every other private symbol here

typealias FMainConnectionID = @convention(c) () -> Int32
typealias FSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
typealias FSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
typealias FShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias FSpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
guard let sky = dlopen(skyLightPath, RTLD_NOW) else {
    print("FAIL: cannot dlopen SkyLight at \(skyLightPath) — nothing below is meaningful.")
    exit(1)
}

// Every lookup is checked. A nil symbol is a result too: it means this macOS
// renamed or dropped the call, and the answer is "not on this system".
func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let p = dlsym(sky, name) else { print("  missing symbol: \(name)"); return nil }
    return unsafeBitCast(p, to: type)
}

guard let SLSMainConnectionID = sym("SLSMainConnectionID", FMainConnectionID.self),
      let SLSSpaceCreate = sym("SLSSpaceCreate", FSpaceCreate.self),
      let SLSSpaceSetAbsoluteLevel = sym("SLSSpaceSetAbsoluteLevel", FSpaceSetAbsoluteLevel.self),
      let SLSShowSpaces = sym("SLSShowSpaces", FShowSpaces.self),
      let SLSSpaceAddWindowsAndRemoveFromSpaces = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", FSpaceAddWindows.self)
else {
    print("FAIL: SkyLight is present but the space API is not the one expected. That IS the result.")
    exit(1)
}

let aboveScreenLock: Int32 = 400   // kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock

// MARK: - The two markers

final class Marker: NSWindow {
    init(screen: NSScreen, label: String, colour: NSColor, yOffset: CGFloat) {
        let size = NSSize(width: 460, height: 120)
        let rect = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.midY - size.height / 2 + yOffset,
            width: size.width, height: size.height
        )
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        // Documented, and the half of this that is not private API: without it
        // AppKit will not show the window while no session is logged in.
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)

        let text = NSTextField(labelWithString: label)
        text.font = .monospacedSystemFont(ofSize: 22, weight: .bold)
        text.textColor = .white
        text.alignment = .center
        text.frame = NSRect(x: 0, y: 34, width: size.width, height: 52)

        let box = NSView(frame: NSRect(origin: .zero, size: size))
        box.wantsLayer = true
        box.layer?.backgroundColor = colour.withAlphaComponent(0.92).cgColor
        box.layer?.cornerRadius = 18
        box.addSubview(text)
        contentView = box
    }
}

guard let screen = NSScreen.main else { print("FAIL: no main screen."); exit(1) }

let raised = Marker(screen: screen, label: "RAISED  (SkyLight space 400)", colour: .systemGreen, yOffset: 80)
let control = Marker(screen: screen, label: "CONTROL (kCGMaximumWindowLevel)", colour: .systemRed, yOffset: -80)
control.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))

raised.orderFrontRegardless()
control.orderFrontRegardless()

// MARK: - Raise one of them out of the default space

let connection = SLSMainConnectionID()
let space = SLSSpaceCreate(connection, 1, 0)
let levelErr = SLSSpaceSetAbsoluteLevel(connection, space, aboveScreenLock)
let showErr = SLSShowSpaces(connection, [space] as CFArray)
let moveErr = SLSSpaceAddWindowsAndRemoveFromSpaces(connection, space, [raised.windowNumber] as CFArray, 7)

print("""

connection      \(connection)
space created   \(space)
setAbsoluteLevel(\(aboveScreenLock))  -> \(levelErr)   (0 = success)
showSpaces                  -> \(showErr)
addWindowsToSpace           -> \(moveErr)

Both markers should be on screen NOW. If either is missing, stop — the probe is
broken and no verdict below counts.

Lock the screen (Control-Command-Q), look, then unlock. Reading:
   both gone    -> NO-GO holds, the space was not the knob
   only GREEN   -> the NO-GO was over-generalised; the space is the knob
   only RED     -> unexpected; report it rather than building on it

Ctrl-C to end.
""")

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
