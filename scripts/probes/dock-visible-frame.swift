// Does the app hear when the Dock changes the room it keeps, and is the visible
// frame already updated when it does?
//
// The Card's HUD keeps its edge margin from where the Dock ends, read off
// NSScreen.visibleFrame (Crema/Windows/ScreenTranslation.swift). That reading is
// taken on each topology pass, which `didChangeScreenParameters` starts; if the
// notification did not fire on a Dock change, or fired before the frame moved, a
// placed HUD would sit under a Dock that just appeared.
//
// Run it, then change the Dock within 30 s: turn "Automatically hide and show
// the Dock" on or off, resize it, or move it to a side (System Settings →
// Desktop & Dock). It prints every screen's visible frame at start (the
// control) and at each notification.
//
// Measured with this probe 2026-10-15, macOS 27.0.1, MacBook Pro 14" (1512×982
// pt), Dock at the bottom, hiding toggled off and back on: start visible
// (0, 0, 1512, 948); off → NOTIFIED with (0, 90, 1512, 858); on → NOTIFIED
// with (0, 0, 1512, 948). One notification per change, frame already moved.
// Invalidated by a Dock change that prints no NOTIFIED line, or one whose
// frame still reads the old value.
//
// Read-only: it never writes a Dock or display setting.
//
// Run: swift scripts/probes/dock-visible-frame.swift
import AppKit

let app = NSApplication.shared

func show(_ tag: String) {
    for screen in NSScreen.screens {
        print(tag, screen.localizedName, "frame", screen.frame, "visible", screen.visibleFrame)
    }
    fflush(stdout)
}

show("start")
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification,
    object: nil,
    queue: .main
) { _ in show("NOTIFIED") }
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    show("end")
    exit(0)
}

app.run()
