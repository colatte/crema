// What does a real vibrancy material sample on a raised space over the lock shield?
//
// The lock card refuses `vibrantSurface` and says why, in a comment that has been
// true since the surface shipped: "that samples what is behind the WINDOW, and
// this window is the size of the screen, so it would sample its own backdrop and
// go flat." The backdrop was deleted (docs/DECISIONS.md: the-lock-surface-is-a-card),
// which retires the reason without answering the question underneath it. Behind
// the window now is the lock shield. Nobody has looked.
//
// It decides the card's material, which — with the backdrop gone — is most of what
// is left to design. `NSVisualEffectView` with `.behindWindow` blending asks the
// WindowServer to composite what is behind the window; a raised SkyLight space at
// absolute level 400 is not an ordinary place to ask that from, and there are three
// plausible answers with three different designs behind them:
//
//   · it samples the shield (wallpaper, avatar, whatever the system drew) → the card
//     can be real glass, and the material is chosen rather than painted.
//   · it samples nothing and renders flat/black → the current `.ultraThinMaterial`
//     over a fill is not a compromise, it is the only honest option, and the design
//     should stop pretending otherwise and commit to an opaque card.
//   · it samples the DESKTOP behind the shield → worse than either, because the card
//     would show content the lock screen exists to hide. That is a finding, not a
//     look, and it would rule the material out on privacy grounds alone.
//
// THE CONTROLS, which is what makes a reading mean something. Four swatches side by
// side, all at the same size, on the same window, in the same space:
//
//   A  .behindWindow  — the question. NSVisualEffectView, .hudWindow material.
//   B  .withinWindow  — the control that separates "vibrancy is broken here" from
//      "there is nothing behind us". B samples this window's own content, which is a
//      known non-empty thing, so if A is flat and B is not, the emptiness is behind
//      the window rather than in the API.
//   C  SwiftUI `.ultraThinMaterial` — what the card ships today, for comparison in
//      the same frame rather than from memory.
//   D  a flat fill at the card's current numbers (black 0.52 + hairline) — the
//      painted-glass baseline. If A and D are indistinguishable, the whole question
//      is moot and the card is already drawing the best available answer.
//
// Each swatch sits over a KNOWN test pattern this probe draws into the window
// itself: without something identifiable behind them, "it sampled something" and
// "it sampled grey" are the same photograph. B should show the pattern. Whether A
// does is the finding.
//
// SECOND QUESTION, free with the first: this app builds against the macOS 26 SDK
// with a macOS 14 deployment target, and Liquid Glass adoption is SDK-linked
// ("absence of the key, or NO, is the default value for apps linking against the
// latest SDKs"). So the same `.ultraThinMaterial` renders one way on Sonoma and
// possibly another on Tahoe, and nobody has seen both. This probe is a plain
// `swift` script — it is NOT the app and does NOT carry the app's Info.plist — so
// swatch C here shows the material WITHOUT whatever the app's own linkage does to
// it. Read C against a screenshot of the shipped app's card rather than against
// intuition; if they differ, the difference is the SDK linkage and it belongs in a
// decision, not in a surprise.
//
// HOW TO READ IT. Run it, lock the screen, look, unlock, Ctrl-C.
//
//   · A shows the wallpaper/shield through it → real vibrancy works up here.
//   · A is flat but B shows the pattern → the API works and there is nothing behind
//     us to sample. Commit to an opaque card.
//   · A shows the DESKTOP (your windows, your work) → stop. Report it. That is a
//     privacy finding and the material is disqualified regardless of how it looks.
//   · A and B both flat → vibrancy does not function in a raised space at all.
//
// Run:  swift scripts/probes/lockscreen-card-material.swift
// Then: lock (Control-Command-Q), look at the four swatches, unlock, Ctrl-C.
//
// Read-only with respect to the app: no preference, no display, no key, and the
// window is `ignoresMouseEvents` so it cannot take a click from the login UI.

import AppKit
import SwiftUI

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

guard let screen = NSScreen.screens.first else { print("no screen"); exit(1) }
let frame = screen.frame
let started = Date()

// MARK: - The test pattern, so "sampled something" is distinguishable from "grey"

/// Drawn INTO this window, behind the swatches. `withinWindow` blending must show
/// it; `behindWindow` must not, because it belongs to us rather than to the shield.
/// Without it the two blending modes are one photograph of a grey rectangle.
final class PatternView: NSView {
    override var isFlipped: Bool { true }

    override func draw(_ dirty: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        bounds.fill()
        let colours: [NSColor] = [.systemRed, .systemYellow, .systemGreen, .systemBlue]
        let bandHeight = bounds.height / CGFloat(colours.count)
        for (i, colour) in colours.enumerated() {
            colour.withAlphaComponent(0.9).setFill()
            NSRect(x: 0, y: CGFloat(i) * bandHeight, width: bounds.width, height: bandHeight).fill()
        }
    }
}

// MARK: - The four swatches

let swatchSide: CGFloat = 260
let gap: CGFloat = 28
let labelHeight: CGFloat = 34

func label(_ text: String, width: CGFloat) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = .monospacedSystemFont(ofSize: 13, weight: .semibold)
    field.textColor = .white
    field.alignment = .center
    field.frame = NSRect(x: 0, y: 0, width: width, height: labelHeight)
    return field
}

/// A rounded swatch carrying the card's own chrome numbers, so what is compared is
/// the material and not the frame around it.
func chrome(_ view: NSView) -> NSView {
    view.wantsLayer = true
    view.layer?.cornerRadius = 22
    view.layer?.cornerCurve = .continuous
    view.layer?.masksToBounds = true
    view.layer?.borderWidth = 0.5
    view.layer?.borderColor = NSColor(white: 0, alpha: 0.35).cgColor
    return view
}

func visualEffect(_ blending: NSVisualEffectView.BlendingMode) -> NSView {
    let effect = NSVisualEffectView()
    effect.material = .hudWindow
    effect.blendingMode = blending
    effect.state = .active
    effect.appearance = NSAppearance(named: .darkAqua)
    return chrome(effect)
}

func swiftUIMaterial() -> NSView {
    let hosting = NSHostingView(rootView:
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(.black.opacity(0.52))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark))
    hosting.sizingOptions = []
    return hosting
}

/// The card as it ships: a flat fill plus the family hairline, no material at all.
func flatFill() -> NSView {
    let view = NSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor(white: 0, alpha: 0.52).cgColor
    return chrome(view)
}

let swatches: [(String, NSView)] = [
    ("A  behindWindow", visualEffect(.behindWindow)),
    ("B  withinWindow  (control)", visualEffect(.withinWindow)),
    ("C  .ultraThinMaterial", swiftUIMaterial()),
    ("D  flat 0.52 + hairline", flatFill()),
]

// MARK: - The window

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
// Non-negotiable: a probe that ate a click aimed at the password field would be
// testing the wrong thing and could strand you.
panel.ignoresMouseEvents = true

let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
root.wantsLayer = true

let totalWidth = CGFloat(swatches.count) * swatchSide + CGFloat(swatches.count - 1) * gap
let originX = (frame.width - totalWidth) / 2
// Centred vertically, which on the author's panel is inside the rectangle the ruler
// proved clear — the probe must not sit on the login any more than the app does.
let originY = (frame.height - swatchSide) / 2

// The pattern spans the whole swatch row plus a margin, so `withinWindow` has
// something to reveal and `behindWindow` has something it should NOT reveal.
let pattern = PatternView(frame: NSRect(
    x: originX - 40, y: originY - 40,
    width: totalWidth + 80, height: swatchSide + 80
))
root.addSubview(pattern)

for (i, entry) in swatches.enumerated() {
    let x = originX + CGFloat(i) * (swatchSide + gap)
    entry.1.frame = NSRect(x: x, y: originY, width: swatchSide, height: swatchSide)
    root.addSubview(entry.1)
    let text = label(entry.0, width: swatchSide)
    text.frame = NSRect(x: x, y: originY - labelHeight - 6, width: swatchSide, height: labelHeight)
    root.addSubview(text)
}

let heading = label(
    "four materials, one space, one pattern behind them — B must show the bands, A is the question",
    width: frame.width
)
heading.frame = NSRect(x: 0, y: originY + swatchSide + 22, width: frame.width, height: labelHeight)
root.addSubview(heading)

panel.contentView = root

// MARK: - The raised space (the five calls the app makes)

typealias MainConnectionID = @convention(c) () -> Int32
typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
typealias SpaceAddWindows = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

let skylight = dlopen(
    "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
)

func sym<T>(_ name: String, _ type: T.Type) -> T? {
    guard let skylight, let pointer = dlsym(skylight, name) else { return nil }
    return unsafeBitCast(pointer, to: T.self)
}

var raised = false
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
    raised = true
} else {
    print("SkyLight did not resolve — this will not survive the lock")
    panel.orderFrontRegardless()
}

signal(SIGINT) { _ in
    print("""

    ran for \(Int(Date().timeIntervalSince(started)))s on \(Int(frame.width))×\(Int(frame.height)) pt
      raised space   \(raised ? "yes" : "NO — it did not survive the lock")

    Record, in words rather than a verdict:
      A  behindWindow  — did it show the shield, nothing, or the desktop?
      B  withinWindow  — did the colour bands come through? (if not, the probe is
                         wrong and A proves nothing)
      C  ultraThinMaterial vs D flat — distinguishable at all?
    """)
    exit(0)
}

print("""
Card-material probe up\(raised ? " on a raised space" : " WITHOUT SkyLight").
Screen \(Int(frame.width))×\(Int(frame.height)) pt.

Lock the screen (Control-Command-Q) and look at the four swatches.
B must show the colour bands — it is the control, and if it does not, ignore A.
Then unlock and Ctrl-C.
""")
app.run()
