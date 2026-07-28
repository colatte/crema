import CoreGraphics
import SwiftUI

/// Notch skin: the surface hugs the physical slit and grows downward when it
/// expands. The frame rule is a pure function of ScreenGeometry (the real notch
/// values arrive from `ScreenTranslation`); the content is `NotchView`.
struct NotchStyle: PresentationStyle {
    /// Directional exit band: laterally the region sits on the clickable menu
    /// bar flanking the slit (keep it tight); below it hangs over app content
    /// (a little more forgiveness); the top edge is the screen edge — pinned,
    /// only reachable where another display stacks above, and the comfort
    /// band alone covers that rare crossing.
    var hoverExitMargins: SurfaceHoverRegions.Margins {
        SurfaceHoverRegions.Margins(top: 0, lateral: 8, bottom: 16)
    }

    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        // No physical notch here → behave like the card. Defensive: the
        // WindowManager also resolves notch→card on non-notch displays, so this
        // rule normally only runs on notched geometry.
        guard geometry.safeTop > 0 else {
            return CardStyle().frame(for: state, on: geometry)
        }

        // The surface anchors at the slit (top edge flush with the screen top,
        // centered on the display) but descends below it: the slit itself is the
        // camera's dead zone, so any content or hover target that lived there
        // would be invisible and would flicker on the cursor's fringe. Every
        // state's height is `safeTop` (the slit, the visual origin) plus a drop
        // into the visible-pixel area below the cutout.
        //
        // Every state stays at the slit width (+ corner bleed): the surface
        // reads as the physical cutout stretching down, Dynamic Island style,
        // and never covers the clickable menu bar that flanks the notch.
        // Expanded only grows the drop; hover exit tracks the current state's
        // rect plus its band, so the hysteresis holds without a state-blind
        // union (docs/DECISIONS.md: hover-follows-the-eye).
        let slitWidth = geometry.frame.width - geometry.auxLeft - geometry.auxRight
        let compactSize = CGSize(
            width: slitWidth - 2 * NotchMetrics.lateralInset,
            height: geometry.safeTop + NotchMetrics.compactDrop
        )
        // Same width in every state: widening would land edges on live pixels
        // beside the slit and move them during the morph — both the lateral
        // residue and the shimmer the design forbids.
        let expandedSize = CGSize(
            width: compactSize.width,
            height: geometry.safeTop + NotchMetrics.expandedDrop
        )

        switch state {
        case .hidden:
            // Collapsed to a point at the slit's center-top, so the show/hide
            // animation converges on the notch.
            return CGRect(x: geometry.frame.midX, y: geometry.frame.maxY, width: 0, height: 0)
        case .nowPlaying(_, expanded: false), .hud:
            return topAnchored(compactSize, on: geometry)
        case .nowPlaying(_, expanded: true):
            return topAnchored(expandedSize, on: geometry)
        }
    }

    /// Centered on the display (the notch is physically centered), anchored
    /// flush with the screen top, lateral edges snapped inward to device
    /// pixels. A fractional slit width (scale modes) would put the surface's
    /// antialiased edge a sub-pixel outside the cutout — near-invisible at
    /// rest, but a visible shimmer while the content animates and the edge
    /// re-rasterizes. Inward, because a half-pixel deficit hides against the
    /// black cutout while an excess sits on live pixels.
    private func topAnchored(_ size: CGSize, on geometry: ScreenGeometry) -> CGRect {
        let scale = max(geometry.scale, 1)
        let left = ((geometry.frame.midX - size.width / 2) * scale).rounded(.up) / scale
        let right = ((geometry.frame.midX + size.width / 2) * scale).rounded(.down) / scale
        return CGRect(
            x: left,
            y: geometry.frame.maxY - size.height,
            width: right - left,
            height: size.height
        )
    }

    /// Click-invoke zone: the physical slit only — dead pixels with no menu
    /// items and no app content under them, so capturing clicks there steals
    /// nothing. Deliberately not the compact frame: its drop band extends
    /// below the menu bar over live window content.
    func invokeZone(on geometry: ScreenGeometry) -> CGRect? {
        guard geometry.safeTop > 0 else { return nil }
        return CGRect(
            x: geometry.frame.minX + geometry.auxLeft,
            y: geometry.frame.maxY - geometry.safeTop,
            width: geometry.frame.width - geometry.auxLeft - geometry.auxRight,
            height: geometry.safeTop
        )
    }

    @MainActor
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> NotchView {
        NotchView(coordinator: coordinator, displayPolicy: displayPolicy)
    }
}

/// The notch's measurements — one place, to calibrate on hardware. All values
/// are design-reference starting points, not absolutes.
enum NotchMetrics {
    /// How far each lateral edge of the animated surface tucks inside the
    /// physical slit. 0 = flush with the cutout — validated on hardware with
    /// the inward device-pixel snap in `topAnchored`: with the edges exactly
    /// on pixel boundaries there is no fractional antialiased fringe for the
    /// height morph to re-rasterize, and no lateral thread. The historical
    /// thread sightings happened with fractional edge positions, where the
    /// recomputed fringe fell on the first live column and shimmered while
    /// animating. Calibrated in both directions: any nonzero tuck reads
    /// recessed (1 pt visibly so; 0.5 pt — one device pixel — faintly), so if
    /// the thread ever returns, raise to 0.5 first, never past 1. The inward
    /// snap collapses anything in (0, 0.5] to that same single pixel.
    /// The slit's rounded corners hold live pixels inside the bounding rect
    /// that the surface's rounded outline doesn't reach — a static full-slit
    /// black underlay in NotchView covers them (static geometry never
    /// re-rasterizes, so its own edges stay clean); and below the slit the
    /// band's lateral edges sit on live pixels by design (a normally visible
    /// edge, like the card's). Never negative — an overhang sits on live
    /// menu-bar pixels even at rest.
    static let lateralInset: CGFloat = 0

    /// How far the surface drops below the slit, into visible pixels. This is
    /// the height of the usable content band (the frame is `safeTop + drop`):
    /// compact/HUD get a small band; expanded gets the media block.
    static let compactDrop: CGFloat = 44
    /// One inset for BOTH compact and HUD content: the two states share the
    /// exact frame, so differing insets would jiggle edges during the
    /// crossfade — the shared constant is what pins them together.
    static let contentPaddingHorizontal: CGFloat = 12
    /// Expanded: the cutout stretching down (Dynamic Island). The width never
    /// changes (see the frame rule); the drop is derived from the reference
    /// layout's stacked sections (header, thin scrubber, transport) — like the
    /// card's — so the band is exactly as tall as its content and no dead
    /// space can pool inside it.
    static var expandedDrop: CGFloat {
        expandedPaddingVertical * 2
            + expandedArtworkSide
            + expandedSectionGap
            + scrubberRowHeight
            + expandedSectionGap
            + controlsHeight
    }

    /// Artwork stays small so the title column keeps ~120 pt of the narrow
    /// surface — a 44 pt cover truncated most real titles.
    static let expandedArtworkSide: CGFloat = 36
    static let expandedArtworkRadius: CGFloat = 9
    static let expandedPaddingHorizontal: CGFloat = 12
    static let expandedPaddingVertical: CGFloat = 12
    /// One gap for the expanded header row (artwork | text).
    static let expandedGap: CGFloat = 10
    static let expandedSectionGap: CGFloat = 8
    static let scrubberRowHeight: CGFloat = 16
    static let controlsHeight: CGFloat = 28
    /// Tighter than the transport's default 10: the band's width scales with
    /// the display's scale mode (the physical cutout is constant), and at the
    /// narrowest 14" mode (1024 pt wide) the content width is ~101 pt — three
    /// 28 pt targets at 8 pt gaps (100 pt) fit; at 10 they overflow the
    /// padding. NotchWidthBudgetTests pins this.
    static let controlsSpacing: CGFloat = 8
    /// The section view-only removes from the expanded drop: the transport row
    /// plus the gap above it — the band shrinks to the visible sections.
    static let controlsSectionHeight: CGFloat = expandedSectionGap + controlsHeight

    /// Corner radii of the surface outline (design-reference §4.1): the base
    /// flares more than the top ("dripping from the notch"), and the surface
    /// opens into wider radii. Top/bottom, in points.
    static let compactTopRadius: CGFloat = 6
    static let compactBottomRadius: CGFloat = 14
    static let expandedTopRadius: CGFloat = 19
    static let expandedBottomRadius: CGFloat = 24

    /// Decorative waveform for the compact band (compact only — expanded has
    /// the scrubber). Shared component; each skin owns its values.
    static let waveform = WaveformGlyph.Configuration(
        barCount: 4,
        barWidth: 2,
        barSpacing: 2.5,
        barCornerRadius: 1,
        restHeight: 4,
        peakHeight: 12,
        pulsePeriod: 0.5
    )
}
