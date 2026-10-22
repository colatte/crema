import AppKit
import SwiftUI

extension View {
    /// Floating-surface material for the Classic skin, and for the Card on
    /// systems before macOS 26, which have no Liquid Glass (the Card on 26 and
    /// later takes `cardSurface`; the notch style is opaque black — it
    /// camouflages with the hardware cutout and takes neither this material nor
    /// the border below: an edge there would draw the very outline that skin
    /// exists to hide).
    ///
    /// Classic stays here by identity: it is the pre-Tahoe bezel, dark and
    /// translucent, and glass would erase what it recalls (docs/DECISIONS.md:
    /// the-card-is-glass). The material is the classic vibrancy one forced active
    /// — public, stable and focus-independent in a never-key panel, where Liquid
    /// Glass draws flat (see the design note).
    ///
    /// The edge is the surface itself: the film (`SurfaceChrome.scrim`) keeps it
    /// dark over any desktop, so it stands out from a bright one on its own, and
    /// the one stroke is an inner specular, brightest at the top and gone within
    /// the upper third, the lit-from-above highlight the material doesn't draw.
    /// No dark rim: around the filled HUD's light sweep it reads as a drawn
    /// outline. The specular is a `strokeBorder`, which is why the shape must be
    /// `InsettableShape`: it insets by half the line width so the highlight stays
    /// inside the surface. Its numbers live in `SurfaceChrome`, which the Settings
    /// tiles read as well — the edge they depict must never become a second
    /// description of this one (docs/DECISIONS.md: surface-border-2026).
    ///
    /// The outline is antialiased once. The content and the film are composited
    /// before the clip, and the material, an AppKit view masked apart from the
    /// SwiftUI layer above it, sits `materialInset` inside the outline: clipped
    /// layer by layer, the dark beneath shows through the edge pixels of a light
    /// fill, a grey fringe round the filled HUD over a bright desktop (measured
    /// with scripts/probes/hud-surface-contrast.swift, mode `edge`).
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
    /// design note (macOS 26, verified 2026-07; macOS 27.0.1, re-measured
    /// 2026-10-15 with scripts/probes/hud-surface-contrast.swift): the vivid Liquid
    /// Glass look in a never-key panel is only reachable via the private
    /// `set_variant:` selector (excluded by project policy); `NSGlassEffectView`
    /// exposes no active-state override, unlike this material's `state = .active`.
    /// Never-key glass draws no specular edge and is as light as this material
    /// over a white page; with semantic ink it follows the system appearance, not
    /// the backdrop. The Card's glass answers both: it strokes the rim itself and
    /// keeps white ink, dimmed where that ink has to read (`cardSurface`).
    func vibrantSurface(in shape: some InsettableShape) -> some View {
        background { SurfaceChrome.scrim }
            .compositingGroup()
            .clipShape(shape)
            .background {
                VibrancyMaterial()
                    .clipShape(shape.inset(by: SurfaceChrome.materialInset))
            }
            .overlay(shape.strokeBorder(SurfaceChrome.specularGradient, lineWidth: SurfaceChrome.specularWidth))
    }
}

/// The floating surface's numbers, in one place: pure and calibratable here,
/// and read by the Settings tiles that draw the same edge in miniature, so the
/// picture and the thing cannot drift apart. The rationale for each lives on
/// `vibrantSurface`, where they are applied: the film carries the boundary, the
/// specular carries the light. Values are starting points to tune on hardware,
/// like SurfaceAnimation's — what must survive a retune is the shape, a dark
/// surface lit at the top, not any single number (docs/DECISIONS.md:
/// surface-border-2026).
enum SurfaceChrome {

    /// The film between the material and the ink, which keeps the surface dark
    /// over any desktop (docs/DECISIONS.md: hud-fixed-dark-palette): set so a
    /// white page behind keeps the white ink at 4.5:1 or better, the material's
    /// worst case. The measurements live in
    /// scripts/probes/hud-surface-contrast.swift; a retune re-runs it over white.
    static let scrimOpacity: Double = 0.44
    static var scrim: Color { Color.black.opacity(scrimOpacity) }

    /// The surface at its lightest, as the contract `scrimOpacity` is set by:
    /// white ink at the minimum over a white page. Ink held to the minimum on
    /// any desktop is held against this.
    static let whiteInkRatioOverWhitePage: Double = WCAGContrast.minimumRatio
    /// The surface at its darkest: white ink measured 19:1 over a black desktop
    /// with scripts/probes/hud-surface-contrast.swift (film 0.44, macOS 27.0.1,
    /// 2026-10-15). Invalidated by a retune of the film or the material; re-run
    /// the probe over black.
    static let whiteInkRatioOverBlackDesktop: Double = 19

    /// How far inside the outline the material stops: one device pixel on a
    /// Retina panel, the antialiased ring where the material would otherwise
    /// darken the edge of a light fill above it (`vibrantSurface`). The ring
    /// shows the film over the desktop instead, unblurred, which no eye resolves
    /// at that width.
    static let materialInset: CGFloat = 0.5

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

    /// The black layer over the Card's Liquid Glass wherever white ink has to
    /// read (`cardSurface`). Measured with scripts/probes/hud-surface-contrast.swift,
    /// mode `tint` (macOS 27.0.1, 2026-10-22): over a white page 0.4 leaves white
    /// ink at 3.99:1 and 0.5 at 5.16:1; over black, 0.5 at 19.8:1. The glass's
    /// own `.tint(.black)` measured the other way, lighter over white (#c1 bare,
    /// #cd at 0.6), which is why the darkening is a layer. Invalidated by a run
    /// where 0.5 falls under 4.5:1 over white.
    static let glassDimOpacity: Double = 0.5
    /// White ink over the dimmed glass at its lightest and darkest, measured with
    /// `glassDimOpacity` above. Both sit inside the band `whiteInkRatioOverWhitePage`
    /// and `whiteInkRatioOverBlackDesktop` bound, so ink held against that band
    /// holds on the glass too.
    static let glassDimmedInkRatioOverWhitePage: Double = 5.16
    static let glassDimmedInkRatioOverBlackDesktop: Double = 19.8
    /// White ink over the BARE glass the slider HUD shows, over a white page: the
    /// same measurement, 1.80:1, under the minimum. Accepted as the system's own
    /// OSD accepts it (about 1.5:1, scripts/probes/native-osd-edge.swift): a bar
    /// read at a glance, and a pale page is where the glass is meant to turn pale
    /// (docs/DECISIONS.md: the-card-is-glass).
    static let glassBareInkRatioOverWhitePage: Double = 1.8

    /// The rim the glass does not draw in a panel that is never key, read off the
    /// system's own OSD (scripts/probes/native-osd-edge.swift, 2026-10-22): white
    /// at about 0.32 along the top, 0.17 down the sides, 0.25 along the bottom,
    /// half a point wide (one device pixel on a Retina panel). A full ring, unlike the specular's top-only ramp,
    /// because the glass carries its own darkness no film is adding here.
    static let glassRimStops: [(location: Double, opacity: Double)] = [
        (0, 0.32),
        (0.5, 0.17),
        (1, 0.25),
    ]
    static let glassRimWidth: CGFloat = 0.5

    /// How far inside the outline the Card's glass stops, the glass's own
    /// `materialInset`, and wider: the glass's blur reaches past its shape.
    /// Measured with scripts/probes/hud-surface-contrast.swift, mode `edge`, over
    /// a white page (macOS 27.0.1, 2026-10-22): at half a point the filled HUD's
    /// leading corner shows a ring (#e4 between a #ee fill and the page), at a
    /// point it is clean (#ed). Invalidated by a run where a point rings.
    static let glassInset: CGFloat = 1

    static var glassRimGradient: LinearGradient {
        LinearGradient(
            stops: glassRimStops.map {
                Gradient.Stop(color: Color.white.opacity($0.opacity), location: CGFloat($0.location))
            },
            startPoint: specularStart,
            endPoint: specularEnd
        )
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
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        // Pinned dark by contract, belt-and-braces with the colorScheme the
        // views force above the surface: the material must not follow a system
        // appearance the ink does not follow (docs/DECISIONS.md:
        // hud-fixed-dark-palette).
        view.appearance = NSAppearance(named: .darkAqua)
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .hudWindow
        view.state = .active
    }
}
