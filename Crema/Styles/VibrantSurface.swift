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
    /// keeps white ink, dimmed under Increase Contrast (`cardSurface`).
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

    /// Whether the Card draws on Liquid Glass: the system has it from macOS 26.
    static var cardIsGlass: Bool {
        if #available(macOS 26, *) {
            true
        } else {
            false
        }
    }

    /// The black layer over the Card's glass under Increase Contrast
    /// (`cardSurface`). Measured with scripts/probes/hud-surface-contrast.swift,
    /// mode `tint`, on the shipped `.clear` glass (macOS 27.0.1, 2026-10-22):
    /// over a white page 0.5 leaves white ink at 4.28:1, 0.55 at 4.94:1 and 0.6
    /// at 5.75:1; over black, 0.55 at 19.6:1. A layer rather than the glass's
    /// tint, which darkens `.clear` (#66 at 0.6) but lightens `.regular`, so a
    /// change of glass would silently invert it. Invalidated by a run where 0.55
    /// falls under 4.5:1 over white.
    static let glassDimOpacity: Double = 0.55

    /// The layer for a contrast setting: none by default, where the Card shows
    /// the glass bare as the system's OSD does; `glassDimOpacity` under Increase
    /// Contrast, which the HIG asks to deliver the minimum.
    static func glassDimming(_ contrast: ColorSchemeContrast) -> Double {
        contrast == .increased ? glassDimOpacity : 0
    }

    /// White ink over the dimmed glass at its lightest and darkest, measured with
    /// `glassDimOpacity` above. Both sit inside the band `whiteInkRatioOverWhitePage`
    /// and `whiteInkRatioOverBlackDesktop` bound, so ink held against that band
    /// under Increase Contrast holds on the glass too.
    static let glassDimmedInkRatioOverWhitePage: Double = 4.94
    static let glassDimmedInkRatioOverBlackDesktop: Double = 19.6
    /// White ink over the BARE glass, over a white page: the same measurement,
    /// 1.42:1, under the minimum. Accepted as the system's own OSD accepts it
    /// (about 1.5:1, scripts/probes/native-osd-edge.swift), and lifted by
    /// Increase Contrast (docs/DECISIONS.md: the-card-is-glass).
    static let glassBareInkRatioOverWhitePage: Double = 1.42

    /// How far inside the outline the Card's glass stops, and how much further
    /// in its own edge is cut. Measured with scripts/probes/hud-surface-contrast.swift,
    /// mode `edge`, the filled HUD's leading corner over a white page: with the
    /// glass flush its blur rings the light fill (#b7 against a #f9 fill); a point
    /// in, clean. The glass also draws its edge darker than its body over a pale
    /// page (#a5 against #d8 down the sides, scripts/probes/native-osd-edge.swift);
    /// cut half a point further in, the sides run #f8 straight into the body.
    static let glassInset: CGFloat = 1
    static let glassEdgeCut: CGFloat = 0.5

    /// The rim the glass does not draw in a never-key panel: three strokes, each
    /// a vertical ramp (top, held from 35% to 75% of the height, bottom), laid so
    /// the Card's edge reads as the system OSD's, pixel by pixel from the outline
    /// in. Measured with scripts/probes/native-osd-edge.swift on captures of both
    /// over a black page (macOS 27.0.1, 2026-10-22):
    ///   top            system #66 #3f #28 into #21, Card #65 #42 #2b into #21
    ///   sides, midway  system about #1b, no rim, Card #1e
    ///   top corners    system #44 #2b, Card #4b #39 #2c
    ///   bottom         system #48 #55, Card #47 #55
    /// The widest stroke spans the band between the outline and the cut glass and
    /// carries the body's tone across it, so the sides show no seam; the two
    /// narrower ones are the light, brightest on top and second at the bottom.
    static let glassRim: [RimStroke] = [
        RimStroke(width: 1.5, top: 0.13, middle: 0.09, bottom: 0.10),
        RimStroke(width: 1, top: 0.09, middle: 0, bottom: 0.14),
        RimStroke(width: 0.5, top: 0.15, middle: 0, bottom: 0.06),
    ]

    /// One stroke of the glass rim: its width and its white opacity along the
    /// top, held through the middle and along the bottom.
    struct RimStroke {
        let width: CGFloat
        let top: Double
        let middle: Double
        let bottom: Double
    }

    static let glassRimHeld: (from: Double, to: Double) = (0.35, 0.75)

    static func glassRimGradient(_ stroke: RimStroke) -> LinearGradient {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color.white.opacity(stroke.top), location: 0),
                Gradient.Stop(color: Color.white.opacity(stroke.middle), location: glassRimHeld.from),
                Gradient.Stop(color: Color.white.opacity(stroke.middle), location: glassRimHeld.to),
                Gradient.Stop(color: Color.white.opacity(stroke.bottom), location: 1),
            ],
            startPoint: specularStart,
            endPoint: specularEnd
        )
    }

    /// The soft shadow under the system's OSD, visible over a white page a few
    /// pixels below its edge (#f1 there); the Card's measures #f2 just under its
    /// edge and #f9 ten pixels down. Over a dark page it is invisible, as the
    /// system's is.
    static let glassShadowOpacity: Double = 0.12
    static let glassShadowRadius: CGFloat = 6
    static let glassShadowY: CGFloat = 2

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
