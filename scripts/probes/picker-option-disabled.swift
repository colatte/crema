// Decides: does a SwiftUI `Picker` in `.menu` style honour `.disabled(true)` on
// one of its options — i.e. can the per-display style popup (Fase 23, Form A)
// grey out "Notch" on a slitless display, or must the popup be a custom `Menu`
// (Form B)? The write-refusal guarantee does NOT depend on this probe: it lives
// in the pure `DisplayStyleOptions.write(for:)`. Only the chrome does.
//
// CONTROL that makes a negative mean something: the same window carries a
// `Menu { Button }` with `.disabled(true)` — a shape that is known to disable —
// plus a `Menu { Toggle }` (measures whether Toggle-in-Menu renders a checkmark,
// which is Form B's chrome). If the control does not read as disabled either,
// the probe's introspection is broken and the verdict is UNVERIFIED, never NO.
//
// Run: swift scripts/probes/picker-option-disabled.swift
// Prints one line per popup item: (title, isEnabled), then the OS version.
// The verdict applies to THIS machine; the app's target is macOS 14.

import AppKit
import SwiftUI

enum Choice: String, CaseIterable, Identifiable {
    case first, second, third
    var id: String { rawValue }
}

struct ProbeView: View {
    @State private var picked: Choice = .first
    @State private var menuOn = false

    var body: some View {
        VStack(spacing: 12) {
            Picker("probe-picker", selection: $picked) {
                ForEach(Choice.allCases) { choice in
                    Text("picker-\(choice.rawValue)")
                        .tag(choice)
                        .disabled(choice == .second)
                }
            }
            .pickerStyle(.menu)

            // The control is AppKit, not SwiftUI `Menu`: a Menu builds its NSMenu
            // lazily on click, so introspection before a click reads nothing —
            // measured, which is why the first run of this probe came back
            // UNVERIFIED. An NSPopUpButton with `autoenablesItems = false` and a
            // natively disabled item is deterministic: if the walker reads THAT
            // as isEnabled=false while the Picker's marked item reads true, the
            // probe can see disabling and the Picker verdict is a clean NO.
            ControlPopUp()
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct ControlPopUp: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.autoenablesItems = false
        button.addItems(withTitles: ["control-enabled", "control-disabled", "control-toggle"])
        button.item(at: 1)?.isEnabled = false
        button.item(at: 2)?.state = .on
        return button
    }

    func updateNSView(_: NSPopUpButton, context _: Context) {}
}

func popUpButtons(in view: NSView) -> [NSPopUpButton] {
    var found: [NSPopUpButton] = []
    if let popUp = view as? NSPopUpButton { found.append(popUp) }
    for sub in view.subviews { found.append(contentsOf: popUpButtons(in: sub)) }
    return found
}

// Menus (the SwiftUI `Menu`) render as NSPopUpButton too on macOS; anything that
// is not, we still catch by walking every NSButton carrying a menu.
func buttonsWithMenus(in view: NSView) -> [(String, NSMenu)] {
    var found: [(String, NSMenu)] = []
    if let button = view as? NSButton, let menu = button.menu ?? (button.cell as? NSPopUpButtonCell)?.menu {
        found.append((button.title, menu))
    }
    for sub in view.subviews { found.append(contentsOf: buttonsWithMenus(in: sub)) }
    return found
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let host = NSHostingView(rootView: ProbeView())
host.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
let window = NSWindow(
    contentRect: host.frame,
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
window.contentView = host
window.orderBack(nil)   // never steals focus; the probe is introspection, not UI

// Give SwiftUI a beat to build the AppKit chrome, then introspect and exit.
DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    let os = ProcessInfo.processInfo.operatingSystemVersion
    var sawPicker = false
    var sawControl = false

    for (title, menu) in buttonsWithMenus(in: host) {
        for item in menu.items {
            print("[\(title)] item '\(item.title)' isEnabled=\(item.isEnabled) state=\(item.state.rawValue)")
            if item.title.hasPrefix("picker-") { sawPicker = true }
            if item.title.hasPrefix("control-") { sawControl = true }
        }
    }

    print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    if !sawPicker || !sawControl {
        print("VERDICT: UNVERIFIED — introspection did not reach \(sawPicker ? "" : "the picker ")\(sawControl ? "" : "the control ")menu items; a missing item list is not a NO.")
    } else {
        print("VERDICT: read the lines above — Form A needs 'picker-second' isEnabled=false AND 'control-disabled' isEnabled=false (the control proves the probe can see disabling at all).")
    }
    exit(0)
}

// Watchdog: a probe that hangs is a probe that lies by silence.
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("VERDICT: UNVERIFIED — probe timed out before introspection.")
    exit(2)
}

app.run()
