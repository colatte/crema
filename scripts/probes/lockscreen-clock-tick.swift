// Does a clock keep ticking on a raised space over the lock shield?
//
// The lock surface draws its own time because its backdrop covers the system's.
// A clock that silently stops is worse than no clock: it shows the minute of the
// lock all night and looks authoritative doing it. Nothing about that window is
// ordinary — it lives in a private SkyLight space at absolute level 400, over a
// shield, in a process macOS has every reason to consider idle — so "the timer
// keeps firing" is exactly the class of claim this surface has already paid for
// once by assuming.
//
// The shipped mechanism is a `Task.sleep` loop over `SleepClock`, chosen over
// `TimelineView(.everyMinute)` because SwiftUI ties timeline schedules to
// whether it believes a view is visible, and that judgement is least trustworthy
// here. But `Task.sleep` is not proven either: App Nap, the timer coalescing
// macOS applies to background processes, and display sleep all sit between the
// intent and the wake.
//
// THE CONTROLS, which is what makes a negative result mean anything. Three
// counters, not one:
//
//   A — TASK.SLEEP, the shipped mechanism. Swift concurrency, cooperative pool.
//   B — DISPATCH TIMER on the main queue, the control. A different scheduler
//       entirely. If A freezes and B does not, the defect is Swift concurrency
//       under whatever macOS does to this process, not the space.
//   R — REDRAWS, incremented inside `draw(_:)`. This separates "the timer never
//       fired" from "the timer fired and the window never repainted", which look
//       identical on screen and need opposite fixes.
//
// Each row shows its count AND the wall time captured at its last fire, so a
// stale reading is distinguishable from a stopped one: a counter that advanced
// while its timestamp did not means the fire happened with a stale date.
//
// HOW TO READ IT. Lock, wait a few minutes, glance at the screen, unlock. Then
// read the summary printed on Ctrl-C, which states how long the run lasted and
// how many times each mechanism should have fired against how many times it did.
//
//   · A and B both track the elapsed minutes → the mechanism is sound; ship it.
//   · A behind, B on track → `Task.sleep` is being held. The clock should move
//     to the dispatch timer, and `LockClockView`'s injected `SleepClock` is the
//     seam that makes that a one-type change.
//   · Both behind but R climbing → the window repaints and nothing schedules.
//   · R frozen while A and B climb → the timers run and the surface does not
//     repaint. That is a rendering problem on the raised space, and no timer
//     change fixes it.
//
// RESULT: not yet run. This header gets the reading the way
// lockscreen-geometry.swift now does — with the display size, the duration, and
// each counter — and an unanswered question stays visibly unanswered rather than
// silently absent.
//
// Run:  swift scripts/probes/lockscreen-clock-tick.swift
// Then: lock (Control-Command-Q), wait, read, unlock. Ctrl-C for the summary.
//
// Read-only with respect to the app: no preference, no display, no key. The
// window is ignoresMouseEvents, so it cannot take a click from the login UI.

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.screens.first else {
    print("no screen"); exit(1)
}

let frame = screen.frame
let started = Date()

/// Shared between the two schedulers and the draw, all of which touch it from
/// the main queue — the Task hops back explicitly for exactly that reason.
final class Ticks: @unchecked Sendable {
    var taskFires = 0
    var taskStamp: Date?
    var dispatchFires = 0
    var dispatchStamp: Date?
    var redraws = 0
}

let ticks = Ticks()

/// The same rule the app ships (`LockClock.secondsUntilNextMinute`), restated
/// here rather than imported: a probe that shares code with the thing it is
/// measuring cannot tell you the code is wrong.
func secondsToNextMinute(_ date: Date) -> Double {
    let into = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
    return 60 - (into < 0 ? into + 60 : into)
}

final class TickView: NSView {
    override var isFlipped: Bool { false }

    override func draw(_ dirty: NSRect) {
        ticks.redraws += 1
        NSColor.black.withAlphaComponent(0.82).setFill()
        bounds.fill()

        let elapsed = Date().timeIntervalSince(started)
        let expected = Int(elapsed / 60)
        var y = bounds.height * 0.62

        func line(_ text: String, size: CGFloat, colour: NSColor) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: size, weight: .semibold),
                .foregroundColor: colour,
            ]
            NSAttributedString(string: text, attributes: attributes)
                .draw(at: CGPoint(x: bounds.width * 0.18, y: y))
            y -= size * 1.7
        }

        let now = Date.FormatStyle(date: .omitted, time: .standard)
        line(Date().formatted(now), size: 64, colour: .white)
        line("running \(Int(elapsed))s — each mechanism owes \(expected) fires", size: 18, colour: .systemGray)
        y -= 12
        line("A  Task.sleep   fires \(ticks.taskFires)"
            + "   last \(ticks.taskStamp.map { $0.formatted(now) } ?? "never")",
            size: 22, colour: ticks.taskFires >= expected ? .systemGreen : .systemRed)
        line("B  Dispatch     fires \(ticks.dispatchFires)"
            + "   last \(ticks.dispatchStamp.map { $0.formatted(now) } ?? "never")",
            size: 22, colour: ticks.dispatchFires >= expected ? .systemGreen : .systemRed)
        line("R  redraws      \(ticks.redraws)", size: 22, colour: .systemTeal)
    }
}

let panel = NSPanel(
    contentRect: frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = false
panel.canBecomeVisibleWithoutLogin = true
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
// Non-negotiable: a probe that ate the password field would lock you out.
panel.ignoresMouseEvents = true
let view = TickView(frame: CGRect(origin: .zero, size: frame.size))
panel.contentView = view

// MARK: - The raised space (the five calls the app makes)

typealias MainConnectionID = @convention(c) () -> Int32
typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)

func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let skylight, let p = dlsym(skylight, name) else { return nil }
    return unsafeBitCast(p, to: T.self)
}

if let cidFn = sym("SLSMainConnectionID", MainConnectionID.self),
   let create = sym("SLSSpaceCreate", SpaceCreate.self),
   let setLevel = sym("SLSSpaceSetAbsoluteLevel", SpaceSetAbsoluteLevel.self),
   let show = sym("SLSShowSpaces", ShowSpaces.self),
   let addWindows = sym("SLSSpaceAddWindowsAndRemoveFromSpaces", SpaceAddWindows.self) {
    let cid = cidFn()
    let space = create(cid, 1, 0)
    _ = setLevel(cid, space, 400)
    _ = show(cid, [space] as CFArray)
    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    _ = addWindows(cid, space, [panel.windowNumber] as CFArray, 7)
} else {
    print("SkyLight did not resolve — this will not survive the lock")
    panel.orderFrontRegardless()
}

// MARK: - A, the shipped mechanism

Task { @MainActor in
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(secondsToNextMinute(Date())))
        ticks.taskFires += 1
        ticks.taskStamp = Date()
        view.needsDisplay = true
    }
}

// MARK: - B, the control on a different scheduler

let dispatchTimer = DispatchSource.makeTimerSource(queue: .main)
dispatchTimer.schedule(
    deadline: .now() + secondsToNextMinute(Date()),
    repeating: .seconds(60),
    leeway: .milliseconds(200)
)
dispatchTimer.setEventHandler {
    ticks.dispatchFires += 1
    ticks.dispatchStamp = Date()
    view.needsDisplay = true
}

dispatchTimer.resume()

// A slow repaint so the seconds on screen stay live without either counted
// mechanism being credited for it — this is what keeps R independent of A and B.
let repaint = DispatchSource.makeTimerSource(queue: .main)
repaint.schedule(deadline: .now() + 1, repeating: .seconds(1))
repaint.setEventHandler { view.needsDisplay = true }
repaint.resume()

signal(SIGINT) { _ in
    let elapsed = Date().timeIntervalSince(started)
    let owed = Int(elapsed / 60)
    print("""

    ran for \(Int(elapsed))s on \(Int(frame.width))×\(Int(frame.height)) pt — each owed \(owed) fires
      A  Task.sleep  \(ticks.taskFires)
      B  Dispatch    \(ticks.dispatchFires)
      R  redraws     \(ticks.redraws)
    """)
    exit(0)
}

print("""
Clock tick probe up on a raised space, screen \(Int(frame.width))×\(Int(frame.height)) pt.
Lock the screen (Control-Command-Q), wait several minutes, glance at it, unlock.
Then Ctrl-C for the summary. A green row is a mechanism keeping up; a red one is
the finding.
""")
app.run()
