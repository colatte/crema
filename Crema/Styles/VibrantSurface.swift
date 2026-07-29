import AppKit
import SwiftUI

extension View {
    /// Floating-surface material for the card and classic skins (the notch
    /// style is opaque black — it camouflages with the hardware cutout and
    /// takes no material).
    ///
    /// We deliberately do not use Liquid Glass here. `glassEffect` renders vivid
    /// only while the window is key/active, and Crema's surface is a never-key
    /// nonactivating LSUIElement panel, so glass there is permanently flat with
    /// no public override (see the design note). Instead we back the surface with
    /// the classic vibrancy material forced active — public, stable, and
    /// focus-independent, so it looks intentional regardless of app focus. The
    /// hairline stroke supplies the highlight the material doesn't draw itself.
    ///
    /// Content is clipped along with the material: mid-morph, the crossfading
    /// outgoing layout can exceed the shrinking surface, and the fixed window
    /// (larger than every state) never crops anything — unclipped, that
    /// overflow ghosts outside the outline.
    ///
    /// Callers pin `.environment(\.colorScheme, .dark)` ENCLOSING this modifier
    /// — that is what flips the AppKit-backed material along with the ink; the
    /// material's own NSAppearance pin below is belt-and-braces and does not
    /// cover the ink (docs/DECISIONS.md: hud-fixed-dark-palette).
    ///
    /// design note (macOS 26, verified 2026-07): the vivid Liquid Glass look in a
    /// never-key panel is only reachable via the private `set_variant:` selector
    /// (excluded by project policy); `NSGlassEffectView` exposes no active-state
    /// override, unlike this material's `state = .active`. To switch back to real
    /// (if flatter) glass, replace the background with
    /// `glassEffect(.regular, in: shape)` under `#available(macOS 26, *)`.
    func vibrantSurface(in shape: some Shape) -> some View {
        background {
            VibrancyMaterial()
                .clipShape(shape)
        }
        .clipShape(shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
}

/// `NSVisualEffectView` forced to the active state so the material stays
/// vibrant even though the panel is never the key window. `.hudWindow` +
/// `.behindWindow` is the system's own HUD/overlay recipe; the panel is already
/// clear + non-opaque, which behind-window blending requires.
private struct VibrancyMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Pinned dark by contract, belt-and-braces with the colorScheme the
        // views force above the surface: the material must not follow a system
        // appearance the ink no longer follows (docs/DECISIONS.md:
        // hud-fixed-dark-palette).
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.state = .active
    }
}
