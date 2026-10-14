// Decides: does SwiftUI menu content reach AppKit's native section headers
// (`NSMenuItem.sectionHeader(title:)`, macOS 14) and item subtitles
// (`NSMenuItem.subtitle`, macOS 14.4) — i.e. can the menu bar menu title its
// groups and put a short line under an item from SwiftUI alone, or does it need
// AppKit? (The anchor is docs/DECISIONS.md: menu-status-before-warnings.)
//
// A SwiftUI `Menu` builds its NSMenu lazily, on open (measured by
// picker-option-disabled.swift), and on macOS 26 it is not an AppKit button a
// script can click. So this probe hands the same content to `NSHostingMenu`
// (macOS 14.4), whose items are "styled and behave identically to views in a
// Menu" (source: Apple docs, NSHostingMenu, read Oct 2026), and reads the NSMenu
// it builds. That `MenuBarExtra`'s `.menu` style goes through that same builder
// is NOT stated by Apple (neither the NSHostingMenu nor the MenuBarExtra page
// says so, read Oct 2026); it is inferred from both turning SwiftUI menu content
// into an NSMenu. So the verdict measures NSHostingMenu, and covers the real
// menu bar menu only by that inference.
//
// CONTROL that makes a negative mean something: the plain `Button("probe-plain")`
// must come back as a titled, enabled item. If it is missing, the probe never saw
// the built menu and the verdict is UNVERIFIED, never NO.
//
// Run: swift scripts/probes/menu-sections-and-subtitles.swift
// Prints one line per item, then the OS version. The verdict applies to THIS
// machine; the app's target is macOS 14.

import AppKit
import SwiftUI

struct ProbeContent: View {
    var body: some View {
        Section("probe-header") {
            Toggle(isOn: .constant(true)) {
                Text("probe-toggle")
                Text("probe-toggle-subtitle")
            }
            Button(action: {}, label: {
                Text("probe-button")
                Text("probe-button-subtitle")
            })
            Text("probe-text")
            Menu {
                Button("probe-inner") {}
            } label: {
                Text("probe-submenu")
                Text("probe-submenu-subtitle")
            }
            Button(action: {}, label: {
                Text("probe-disabled")
                Text("probe-disabled-subtitle")
            })
            .disabled(true)
        }
        Divider()
        Button("probe-plain") {}
    }
}

func describe(_ item: NSMenuItem) -> String {
    var parts = ["'\(item.title)'"]
    if item.isSeparatorItem { parts.append("separator") }
    if item.isSectionHeader { parts.append("sectionHeader") }
    if let subtitle = item.subtitle { parts.append("subtitle='\(subtitle)'") }
    if item.hasSubmenu { parts.append("submenu") }
    parts.append("enabled=\(item.isEnabled)")
    parts.append("state=\(item.state.rawValue)")
    return parts.joined(separator: " ")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let menu = NSHostingMenu(rootView: ProbeContent())

DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
    menu.update()
    menu.items.forEach { print(describe($0)) }
    let os = ProcessInfo.processInfo.operatingSystemVersion
    print("macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)")
    if menu.items.contains(where: { $0.title == "probe-plain" }) {
        print("VERDICT: read the lines above — sections reach AppKit if 'probe-header' is a sectionHeader item; subtitles do if the toggle, button, submenu and disabled lines carry subtitle=.")
    } else {
        print("VERDICT: UNVERIFIED — the control item 'probe-plain' was not read; the built menu was never seen.")
    }
    exit(0)
}

// Watchdog: a probe that hangs is a probe that lies by silence.
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("VERDICT: UNVERIFIED — probe timed out before introspection.")
    exit(2)
}

app.run()
