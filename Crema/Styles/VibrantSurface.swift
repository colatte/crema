import AppKit
import SwiftUI

extension View {
    /// Floating-surface material for the card and classic skins (the notch
    /// style is opaque black — it camouflages with the hardware cutout and
    /// takes neither this material nor the border below: an edge there would
    /// draw the very outline that skin exists to hide).
    ///
    /// We deliberately do not use Liquid Glass here. `glassEffect` renders vivid
    /// only while the window is key/active, and Crema's surface is a never-key
    /// nonactivating LSUIElement panel, so glass there is permanently flat with
    /// no public override (see the design note). Instead we back the surface with
    /// the classic vibrancy material forced active — public, stable, and
    /// focus-independent, so it looks intentional regardless of app focus.
    ///
    /// The border is a PAIR, and neither half does the other's job: a darkened
    /// outer rim straddling the outline DEFINES the surface against any backdrop
    /// — a light hairline disappears over a bright desktop, which is where a
    /// floating surface most needs an edge — while an inner specular, brightest
    /// at the top and gone within the upper third, supplies the lit-from-above
    /// highlight the material doesn't draw itself. The specular is a
    /// `strokeBorder`, which is why the shape must be `InsettableShape`: it
    /// insets by half the line width so the highlight stays inside the surface
    /// instead of bleeding a bright edge outward, past the rim that is supposed
    /// to be the outermost thing here. Both live in `SurfaceChrome`, which the
    /// Settings tiles read as well — the border they depict must never become a
    /// second description of this one (docs/DECISIONS.md: surface-border-2026).
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
    /// `material` defaults to what the desktop skins have always used. The lock
    /// card passes `.underWindowBackground` instead, and the difference is not
    /// taste: measured, `.hudWindow` tints white 0.1569 at alpha 0.40 while
    /// `.underWindowBackground` does it at 0.80, so the ground under the ink is
    /// twice as certain over an arbitrary wallpaper. Apple's abstract for that
    /// material is the only one in the catalogue carrying a discussion, and it
    /// describes this case — "use this material on a visual effect view with a
    /// blendingMode of behindWindow to create a sense of peeking through the
    /// back of the window."
    ///
    /// The parameter is the material and NOTHING ELSE. The rim and the specular
    /// stay shared, because those are the numbers a surface must not drift on.
    func vibrantSurface(
        in shape: some InsettableShape,
        material: NSVisualEffectView.Material = .hudWindow
    ) -> some View {
        background {
            VibrancyMaterial(material: material)
                .clipShape(shape)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(SurfaceChrome.specularGradient, lineWidth: SurfaceChrome.specularWidth))
        // Last, so the boundary is never dimmed by the highlight that touches
        // it: the two strokes are adjacent by half a point each.
        .overlay(shape.stroke(SurfaceChrome.outerHairlineColor, lineWidth: SurfaceChrome.outerHairlineWidth))
    }
}

/// The surface border's numbers, in one place: pure and calibratable here, and
/// read by the Settings tiles that draw the same border in miniature, so the
/// picture and the thing cannot drift apart.
///
/// Why a pair of strokes (the rationale for each half lives on `vibrantSurface`,
/// where they are applied): the rim carries the boundary, the specular carries
/// the light. Values are starting points to tune on hardware, like
/// SurfaceAnimation's — what must survive a retune is the shape of the border,
/// not any single number (docs/DECISIONS.md: surface-border-2026).
enum SurfaceChrome {
    /// The rim as a white component (0 is black) plus its opacity — one number
    /// for how dark, one for how present. It reads as a shadow of an edge
    /// rather than an edge: over a bright desktop that is the only thing that
    /// keeps the surface's outline; over a dark one the specular carries it.
    static let outerHairlineWhite: Double = 0
    static let outerHairlineOpacity: Double = 0.35
    static let outerHairlineWidth: CGFloat = 0.5

    /// The specular's opacity at the very top of the surface.
    static let specularTopOpacity: Double = 0.35

    /// The highlight ramp along the surface's height, as (fraction from the
    /// top, white opacity). It is spent within the upper third: a highlight
    /// still alive at the bottom edge stops reading as light from above and
    /// starts reading as a ring around the surface. The trailing stop is
    /// explicit — SwiftUI would extend the last color anyway, but the ramp's
    /// end is part of the contract, not an inherited default.
    static let specularStops: [(location: Double, opacity: Double)] = [
        (0, specularTopOpacity),
        (0.35, 0),
        (1, 0),
    ]
    static let specularWidth: CGFloat = 0.5

    /// The ramp's axis. Separate constants because the stop locations only mean
    /// "from the top" while these say so — swapping them lights the bottom edge
    /// with the same numbers.
    static let specularStart: UnitPoint = .top
    static let specularEnd: UnitPoint = .bottom

    /// What a Settings tile strokes: it draws ONE flat hairline where the real
    /// surface draws a ramp, so it takes the ramp's brightest point and may
    /// only go brighter — at thumbnail scale an edge that fades reads as no
    /// edge. Derived, never a literal: a forked number here paints a border the
    /// app doesn't have, in the one place the user compares the skins.
    static let tileStrokeTopOpacity: Double = specularTopOpacity

    static var outerHairlineColor: Color {
        Color(white: outerHairlineWhite).opacity(outerHairlineOpacity)
    }

    static var specularGradient: LinearGradient {
        LinearGradient(
            stops: specularStops.map {
                Gradient.Stop(color: Color.white.opacity($0.opacity), location: CGFloat($0.location))
            },
            startPoint: specularStart,
            endPoint: specularEnd
        )
    }
}

/// `NSVisualEffectView` forced to the active state so the material stays
/// vibrant even though the panel is never the key window. `.hudWindow` +
/// `.behindWindow` is the system's own HUD/overlay recipe; the panel is already
/// clear + non-opaque, which behind-window blending requires.
private struct VibrancyMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Pinned dark by contract, belt-and-braces with the colorScheme the
        // views force above the surface: the material must not follow a system
        // appearance the ink no longer follows (docs/DECISIONS.md:
        // hud-fixed-dark-palette).
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.state = .active
    }
}
