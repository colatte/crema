// Can a click-through window over the lock shield learn where the cursor is?
//
// `lockscreen-events.swift` proved that clicks REACH a raised-space window while
// locked. It said nothing about the window that is deliberately NOT taking them.
// That gap became load-bearing: the lock panel is the size of the display, and a
// clear window that size captures every click on the lock screen — the password
// field included — so it now ships `ignoresMouseEvents = true` and opens only
// where the card is drawn. Opening it needs the cursor's position.
//
// Apple's own words are the reason this probe exists rather than an assumption:
//
//   "A global event monitor looks for user-input events dispatched to
//    applications other than the one in which it is installed. […] A global
//    event monitor would not be able to detect Command-Tab or a system alert."
//   — Monitoring Events, Cocoa Event Handling Guide (archived)
//
// The lock screen is loginwindow's UI. If "system alert" generalizes to it, the
// monitor never fires there and the card is never clickable — safe, but dead.
//
// THREE MECHANISMS, measured side by side, because they fail independently:
//
//   GLOBAL   NSEvent.addGlobalMonitorForEvents(.mouseMoved). What the code
//            currently uses. Event DELIVERY to our process.
//   LOCAL    NSEvent.addLocalMonitorForEvents(.mouseMoved). Only fires while the
//            window is taking events, so it can never be the thing that decides
//            to start taking them — measured to show which side of the boundary
//            each mechanism lives on.
//   POLL     NSEvent.mouseLocation, read on a timer. Not a subscription: it asks
//            the WindowServer where the cursor is. If delivery is what breaks
//            over the shield, this is the fallback the panel would switch to.
//
// THE CONTROL, without which a silent log proves nothing: every mechanism is
// sampled in both states, and the probe stamps each sample with the lock bit it
// read itself from CGSessionCopyCurrentDictionary. Counts while UNLOCKED prove
// the mechanism works at all; the same counts while LOCKED are the answer.
//
//   global > 0 locked          -> the shipped routing works; nothing to change.
//   global == 0, poll moving   -> switch the panel to polling the cursor.
//   both dead locked           -> no single-window routing is possible; the card
//                                 needs its own small window (which
//                                 lockscreen-events.swift already proved takes
//                                 clicks there), and the screen-sized one stays
//                                 click-through forever.
//
// RESULT, 2026-08-07 (macOS 26, Apple Silicon, run by the author). The first
// outcome: the routing the app ships works over the shield.
//
//                unlocked   locked
//     GLOBAL             0     1092   ALIVE WHILE LOCKED
//     LOCAL            721      281   ALIVE WHILE LOCKED
//     POLL              62      117   ALIVE WHILE LOCKED
//
// So Apple's "not able to detect [...] a system alert" does NOT generalize to
// the lock shield: mouse-moved is delivered to a global monitor there, with the
// window in exactly the configuration being diagnosed.
//
// TWO THINGS THE RUN TAUGHT THAT THE DESIGN DID NOT ANTICIPATE:
//
// 1. The global monitor was silent UNLOCKED and loud LOCKED — the reverse of
//    what the control was built to show. It is consistent with the documented
//    definition (a global monitor excludes events dispatched to its OWN app, and
//    unlocked they went to ours: LOCAL 721), but the explanation is not what
//    rescues the reading. The reading is POSITIVE on the side that matters, and
//    a positive reading needs no control — the control exists so that a ZERO can
//    be told apart from a broken probe. Keep this straight before quoting the
//    table: the 0 in the unlocked column is not a failed measurement of the
//    thing being measured.
//
// 2. POLL is alive too, which makes it a live fallback rather than a hypothesis.
//    If a future macOS stops delivering to the global monitor, the panel swaps
//    one mechanism for the other inside `installMouseRouting` and nothing else
//    moves. That is the reason all three were measured instead of stopping at
//    the first success.
//
// The window here is screen-sized and ignoresMouseEvents = true, exactly like
// the one being diagnosed — and that flag is also what keeps this probe from
// being one that locks you out of your Mac.
//
// Run:  swift scripts/probes/lockscreen-mouse-routing.swift
// Then: move the mouse in circles for ~5 s, lock (Control-Command-Q), move it in
//       circles again for ~10 s, unlock. Read the table. Ctrl-C to end.
//
// Read-only with respect to the app: no preference, no display, no key.

import AppKit

// MARK: - Lock state, read rather than inferred

func screenIsLocked() -> Bool {
    guard let info = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
    return info["CGSSessionScreenIsLocked"] as? Int == 1
}

// MARK: - Counters, one per mechanism per lock state

final class Tally {
    var globalUnlocked = 0, globalLocked = 0
    var localUnlocked = 0, localLocked = 0
    var pollUnlocked = 0, pollLocked = 0
    var lastPollPoint = CGPoint.zero

    /// The locked count is asked FIRST, and the ordering is the lesson of the
    /// 2026-08-07 run: the global monitor read 0 unlocked and 1092 locked, and
    /// an earlier version of this function called that "inconclusive" because
    /// the control was silent. It is not. A control exists to give meaning to a
    /// SILENCE — and there was no silence on the side being measured. A positive
    /// reading stands on its own; only a zero needs the control to tell "not
    /// delivered here" apart from "probe broken".
    func line(_ name: String, _ unlocked: Int, _ locked: Int) -> String {
        let verdict: String
        if locked > 0 {
            verdict = unlocked > 0
                ? "ALIVE WHILE LOCKED"
                : "ALIVE WHILE LOCKED (and silent unlocked — see the note below)"
        } else if unlocked == 0 {
            verdict = "NO READING AT ALL — move the mouse more, or the probe is broken"
        } else {
            verdict = "DEAD WHILE LOCKED"
        }
        return String(format: "  %-7@ unlocked %5d | locked %5d   %@",
                      name as NSString, unlocked, locked, verdict as NSString)
    }

    func report() {
        print("\n=== lock-screen mouse routing ===")
        print(line("GLOBAL", globalUnlocked, globalLocked))
        print(line("LOCAL", localUnlocked, localLocked))
        print(line("POLL", pollUnlocked, pollLocked))
        print("""

        POLL counts only samples where the cursor actually MOVED since the last
        one, so a frozen reading cannot masquerade as a live one.
        """)
    }
}

let tally = Tally()

// MARK: - The window being diagnosed

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.screens.first else {
    print("no screen"); exit(1)
}

let panel = NSPanel(
    contentRect: screen.frame,
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isFloatingPanel = true
panel.isOpaque = false
panel.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.10)
panel.hasShadow = false
panel.canBecomeVisibleWithoutLogin = true
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
panel.level = NSWindow.Level(rawValue: Int(Int32.max) - 2)
// The whole point: this window must never take a click away from the login UI.
panel.ignoresMouseEvents = true

// MARK: - The raised space (same five calls the app makes)

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
    panel.orderFrontRegardless()
    _ = addWindows(cid, space, [panel.windowNumber] as CFArray, 7)
    print("raised space \(space) at absolute level 400")
} else {
    print("SkyLight did not resolve — the window will sit behind the shield; results are meaningless")
    panel.orderFrontRegardless()
}

// MARK: - The three mechanisms

NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { _ in
    if screenIsLocked() { tally.globalLocked += 1 } else { tally.globalUnlocked += 1 }
}
NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
    if screenIsLocked() { tally.localLocked += 1 } else { tally.localUnlocked += 1 }
    return event
}

// 100 ms, which is also the interval the panel would use if this is the winner:
// a click is preceded by the cursor arriving, so a tenth of a second of lead is
// invisible to the hand and cheap enough to run through a whole night's lock.
Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
    let point = NSEvent.mouseLocation
    defer { tally.lastPollPoint = point }
    guard point != tally.lastPollPoint else { return }
    if screenIsLocked() { tally.pollLocked += 1 } else { tally.pollUnlocked += 1 }
}

// A running table, so the author sees it working before locking rather than
// discovering afterwards that nothing was ever counted.
Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in tally.report() }

var lastLocked = screenIsLocked()
Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
    let now = screenIsLocked()
    if now != lastLocked {
        print("\n--- screen \(now ? "LOCKED" : "UNLOCKED") ---")
        lastLocked = now
    }
}

print("""
Move the mouse in circles for ~5 s, then lock (Control-Command-Q), circle again
for ~10 s, unlock, and read the last table. Ctrl-C to end.
""")
app.run()
