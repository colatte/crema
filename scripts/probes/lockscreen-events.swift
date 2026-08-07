// Do EVENTS reach a raised-space window over the lock shield, and does a
// screen-sized one behave there?
//
// `lockscreen-space.swift` proved that PIXELS reach the lock screen: a window
// moved into a SkyLight space at absolute level 400 survives the shield while
// an ordinary window at kCGMaximumWindowLevel does not. It answered nothing
// else, and the investigation says so in as many words — "not proven, and not
// to be assumed: … that a raised space behaves for hover, click routing or
// multi-display the way the app's panels do today."
//
// The lock-screen now-playing widget rests on two of those. Its expanded state
// exists only if a click lands, and expanding covers the display, which the
// 460x120 marker never tested. Both are settled here, before any surface code.
//
// RESULT, 2026-08-07 (macOS 26, Apple Silicon, run by the author):
//   · 5 clicks logged `unlocked` — the control; clicks reach this window at all.
//   · 10 clicks logged `LOCKED`  — EVENTS REACH a raised-space window over the
//     shield. The widget's expanded state is viable.
//   · Both windows stayed visible across three lock/unlock cycles, so a
//     SCREEN-SIZED window in the raised space behaves like the small one.
//   · macOS drew NO media controls of its own on the lock screen: this feature
//     is not a second player.
//   · NOT ANSWERED — no sleep, wake or hotplug edge fired during the run, so
//     the log carries no EDGE line. Whether the space survives them is still
//     open; the app treats those edges as WindowServer-invalidating anyway
//     (docs/DECISIONS.md: preventive-reinstall), so the widget re-adds its
//     window to the space on each of them rather than trusting they are safe.
//     Re-run and sleep the display to close it properly.
//
// Run:  swift scripts/probes/lockscreen-events.swift
// Then: click the button, lock the screen (Control-Command-Q), click it again,
//       unlock, and read the log. Ctrl-C to end.
//
// TWO WINDOWS, and the split is what keeps this safe as well as legible:
//
//   BUTTON    small, bottom-left, accepts mouse events. Answers question 1.
//   BACKDROP  the whole display, 22% tint, ignoresMouseEvents = true.
//             Answers question 2 and can never swallow a click meant for the
//             password field — a screen-sized window that ate events over the
//             lock shield would be a probe that locks you out of your Mac.
//
// THE CONTROL, without which a silent log means nothing: the probe reads the
// session dictionary itself and stamps every click with the lock state at the
// moment it arrived. So the log distinguishes the three outcomes on its own —
//
//   clicks logged UNLOCKED and LOCKED  -> events reach; the expanded state ships.
//   clicks logged UNLOCKED only        -> pixels yes, events no; no second state.
//   no clicks at all                   -> the probe is broken; neither result counts.
//
// It also reports display sleep/wake and screen-parameter edges, because the
// panel layer already treats those as WindowServer-invalidating
// (docs/DECISIONS.md: preventive-reinstall) and nobody has checked whether a
// raised space needs the same. Local visibility reads are logged for what they
// are worth and no more: the J7 lesson in this codebase is that state living
// beyond WindowServer cannot be audited from inside the process, so the
// author's eyes are the instrument and these numbers are a hint.
//
// Read-only with respect to the app: no preference, no display, no key.

import AppKit

// MARK: - SkyLight, resolved at runtime like every other private symbol here

typealias FMainConnectionID = @convention(c) () -> Int32
typealias FSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
typealias FSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
typealias FShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias FSpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

let skyLightPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
guard let sky = dlopen(skyLightPath, RTLD_NOW) else {
    print("FAIL: cannot dlopen SkyLight — nothing below is meaningful.")
    exit(1)
}

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

// MARK: - Lock state, read the way the app reads it

/// `CGSessionCopyCurrentDictionary` is the authoritative read the app already
/// trusts (`ScreenLockSessionTranslation`); the notification edges are not used
/// here because this probe only ever asks "right now", never "did it change".
func lockState() -> (locked: Bool, onConsole: Bool, readable: Bool) {
    guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else {
        return (false, false, false)
    }
    let locked = dict["CGSSessionScreenIsLocked"] as? Bool ?? false
    let onConsole = dict["kCGSSessionOnConsoleKey"] as? Bool ?? true
    return (locked, onConsole, true)
}

let started = Date()
func stamp() -> String {
    let s = lockState()
    let where_ = !s.readable ? "UNREADABLE" : (s.locked ? "LOCKED  " : "unlocked")
    return String(format: "[%6.1fs] %@ onConsole=%@", Date().timeIntervalSince(started),
                  where_, s.onConsole ? "yes" : "NO ")
}

func log(_ message: String) {
    print("\(stamp())  \(message)")
    fflush(stdout)
}

// MARK: - The two windows

final class RaisedWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(frame: NSRect, acceptsClicks: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = !acceptsClicks
        // The public half the level sweep also missed: without it AppKit will
        // not show the window while no session is logged in.
        canBecomeVisibleWithoutLogin = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
    }
}

/// The click target. A plain NSView reporting mouseDown itself rather than an
/// NSButton, so the log records the raw event arriving and not AppKit's
/// interpretation of it.
final class ClickPad: NSView {
    var clicksUnlocked = 0
    var clicksLocked = 0
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.92).cgColor
        layer?.cornerRadius = 16
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = NSRect(x: 12, y: 20, width: frame.width - 24, height: 60)
        label.maximumNumberOfLines = 3
        addSubview(label)
        repaint()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if lockState().locked { clicksLocked += 1 } else { clicksUnlocked += 1 }
        log("CLICK RECEIVED  (unlocked: \(clicksUnlocked), locked: \(clicksLocked))")
        repaint()
    }

    func repaint() {
        label.stringValue = "CLIQUE AQUI\nunlocked \(clicksUnlocked)  ·  locked \(clicksLocked)"
    }
}

guard let screen = NSScreen.main else { print("FAIL: no main screen."); exit(1) }

// BACKDROP — the whole display, never eats a click.
let backdrop = RaisedWindow(frame: screen.frame, acceptsClicks: false)
let tint = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
tint.wantsLayer = true
tint.layer?.backgroundColor = NSColor.systemPurple.withAlphaComponent(0.22).cgColor
let corner = NSTextField(labelWithString: "BACKDROP — janela do tamanho da tela, no space elevado")
corner.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
corner.textColor = NSColor.white.withAlphaComponent(0.85)
corner.frame = NSRect(x: 24, y: screen.frame.height - 60, width: 720, height: 22)
tint.addSubview(corner)
backdrop.contentView = tint

// BUTTON — bottom-left, out of the password field's way.
let padSize = NSSize(width: 260, height: 110)
let pad = ClickPad(frame: NSRect(origin: .zero, size: padSize))
let button = RaisedWindow(
    frame: NSRect(x: screen.frame.minX + 60, y: screen.frame.minY + 90,
                  width: padSize.width, height: padSize.height),
    acceptsClicks: true
)
button.contentView = pad

backdrop.orderFrontRegardless()
button.orderFrontRegardless()

// MARK: - Raise both out of the default space

let connection = SLSMainConnectionID()
let space = SLSSpaceCreate(connection, 1, 0)
let levelErr = SLSSpaceSetAbsoluteLevel(connection, space, aboveScreenLock)
let showErr = SLSShowSpaces(connection, [space] as CFArray)
let moveErr = SLSSpaceAddWindowsAndRemoveFromSpaces(
    connection, space, [backdrop.windowNumber, button.windowNumber] as CFArray, 7
)

// MARK: - Edges the panel layer already treats as WindowServer-invalidating

let workspaceCenter = NSWorkspace.shared.notificationCenter
for (name, label) in [
    (NSWorkspace.screensDidSleepNotification, "screens slept"),
    (NSWorkspace.screensDidWakeNotification, "screens woke"),
    (NSWorkspace.didWakeNotification, "system woke"),
    (NSWorkspace.sessionDidResignActiveNotification, "session resigned (fast user switch)"),
    (NSWorkspace.sessionDidBecomeActiveNotification, "session became active"),
] {
    workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
        log("EDGE: \(label)")
    }
}

NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in log("EDGE: screen parameters changed (hotplug/resolution)") }

// MARK: - Heartbeat

/// `isVisible` and `occlusionState` are local reads about state that lives in
/// the WindowServer, which is exactly the class of lie J7 is about. Logged as a
/// hint, never as the verdict — the verdict is whether the author still sees
/// the two rectangles.
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
    let b = backdrop.isVisible ? "visible" : "NOT VISIBLE"
    let k = button.isVisible ? "visible" : "NOT VISIBLE"
    log("heartbeat — backdrop \(b), button \(k)  (local reads; trust your eyes)")
}

// Belt and braces: never leave a tint over someone's Mac forever.
Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { _ in
    log("10 minutes elapsed — tearing down so nothing is left on screen.")
    backdrop.orderOut(nil)
    button.orderOut(nil)
    NSApplication.shared.terminate(nil)
}

print("""

connection      \(connection)
space created   \(space)
setAbsoluteLevel(\(aboveScreenLock))  -> \(levelErr)   (0 = success)
showSpaces                  -> \(showErr)
addWindowsToSpace           -> \(moveErr)

Two things should be on screen NOW: a purple tint over the whole display, and a
green CLIQUE AQUI pad at the bottom left. If either is missing, stop — the probe
is broken and no verdict below counts.

  1. Click the pad a few times. The counter must move, and the log must say
     "unlocked". That is the control: it proves clicks reach this window at all.
  2. Lock the screen (Control-Command-Q).
  3. Look: is the purple tint still there over the lock screen? Is the pad?
     While you are there — does macOS draw its OWN media controls on the lock
     screen? If it does, this feature would be the second player.
  4. Click the pad while locked.
  5. Unlock and read the log below.

Reading:
  clicks logged unlocked AND locked -> events reach; the expanded state ships
  clicks logged unlocked only       -> pixels yes, events no; no second state
  no clicks at all                  -> probe broken; neither result counts

Auto-teardown in 10 minutes. Ctrl-C to end sooner.

""")
log("probe armed")

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.run()
