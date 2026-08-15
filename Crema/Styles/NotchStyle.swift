import CoreGraphics
import SwiftUI

/// Notch skin: the surface hugs the physical slit and grows downward when it
/// expands. The frame rule is a pure function of ScreenGeometry (the real notch
/// values arrive from `ScreenTranslation`); the content is `NotchView`.
struct NotchStyle: PresentationStyle {
    /// Directional exit band: laterally the region sits on the clickable menu
    /// bar flanking the slit — kept tight (5 pt, hardware-calibrated), which
    /// the overshoot pin admits because the lateral edges are static: the
    /// width is invariant across the VISIBLE states (the morph only travels
    /// height), and the empty crossing never travels geometry at all (a fade
    /// at the final rect — CLAUDE.md, animation contract 1). Below, the band
    /// hangs over app content (a little more forgiveness); the top edge is
    /// the screen edge — pinned, only reachable where another display stacks
    /// above, and the comfort band alone covers that rare crossing.
    var hoverExitMargins: SurfaceHoverRegions.Margins {
        SurfaceHoverRegions.Margins(top: 0, lateral: 5, bottom: 16)
    }

    /// The physical slit as a rect, or nil when this geometry describes no notch
    /// the skin can hug. The ONE place that answers where the cutout is: the
    /// surface, the click-invoke zone, the Settings picture and the declared→drawn
    /// resolver all ask it, so none of them can claim a pixel another one disowns
    /// (docs/DECISIONS.md: the-slit-is-found-from-its-edges).
    ///
    /// Built from the two EDGES the API gives — the auxiliary areas flanking the
    /// safe-area strip — and never from the display's centre. A centre is an
    /// inference that the cutout is symmetric, and the measured 14" panel is not
    /// (663 pt left, 664 right): the inferred centre sits half a point right of
    /// the real one, enough to put the surface's right edge on live menu-bar
    /// pixels that `NotchMetrics.lateralInset`'s flush calibration forbids.
    ///
    /// Empty auxiliary areas are NOT a notch, whatever `safeTop` reports:
    /// `NSScreen.h` documents both rects as "empty if there are no additional
    /// unobscured areas", so a full-width safe area is a display with nothing
    /// beside the obscured strip. Answering that with a slit as wide as the
    /// screen would weld a display-wide surface to the top edge and hand the
    /// invoke zone the entire menu bar, which the panel then captures the mouse
    /// inside for clicks `Coordinator.invoke` mostly refuses.
    static func slit(on geometry: ScreenGeometry) -> CGRect? {
        let width = geometry.frame.width - geometry.auxLeft - geometry.auxRight
        guard geometry.safeTop > 0, width > 0, width < geometry.frame.width else { return nil }
        return CGRect(
            x: geometry.frame.minX + geometry.auxLeft,
            y: geometry.frame.maxY - geometry.safeTop,
            width: width,
            height: geometry.safeTop
        )
    }

    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        // No slit to hug here → behave like the card. Defensive only: the render
        // rule (`Style.resolved(on:)`) already maps notch→card on such a display,
        // asking this same slit rule, so this branch normally never runs.
        guard let slit = Self.slit(on: geometry) else {
            return CardStyle().frame(for: state, on: geometry)
        }

        // The surface anchors at the slit (top edge flush with the screen top,
        // centered in the SLIT) but descends below it: the slit itself is the
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
        let compactSize = CGSize(
            width: slit.width - 2 * NotchMetrics.lateralInset,
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
            return CGRect(x: slit.midX, y: geometry.frame.maxY, width: 0, height: 0)
        case .nowPlaying(_, expanded: false), .hud:
            return topAnchored(compactSize, centeredIn: slit, on: geometry)
        case .nowPlaying(_, expanded: true):
            return topAnchored(expandedSize, centeredIn: slit, on: geometry)
        }
    }

    /// Centered in the slit — the cutout's own centre, derived from the rect
    /// `slit(on:)` built out of the two edges, never the display's midX (the
    /// hardware is not obliged to be symmetric, and this one is not). Anchored
    /// flush with the screen top, lateral edges snapped inward to device
    /// pixels. A fractional slit width (scale modes) would put the surface's
    /// antialiased edge a sub-pixel outside the cutout — near-invisible at
    /// rest, but a visible shimmer while the content animates and the edge
    /// re-rasterizes. Inward, because a half-pixel deficit hides against the
    /// black cutout while an excess sits on live pixels.
    private func topAnchored(_ size: CGSize, centeredIn slit: CGRect, on geometry: ScreenGeometry) -> CGRect {
        let scale = max(geometry.scale, 1)
        let left = ((slit.midX - size.width / 2) * scale).rounded(.up) / scale
        let right = ((slit.midX + size.width / 2) * scale).rounded(.down) / scale
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
    /// below the menu bar over live window content. It IS `slit(on:)`'s rect
    /// rather than a second derivation of it: the panel takes the mouse inside
    /// this zone, so a zone that reaches a pixel the surface disowns captures
    /// clicks over live menu bar (docs/DECISIONS.md: the-slit-is-found-from-its-edges).
    func invokeZone(on geometry: ScreenGeometry) -> CGRect? {
        Self.slit(on: geometry)
    }

    @MainActor
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> NotchView {
        NotchView(coordinator: coordinator, displayPolicy: displayPolicy)
    }
}

/// The notch's measurements — one place, to calibrate on hardware. All values
/// are research starting points, not absolutes.
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
    /// Compact band content: the small cover with its single-line title and
    /// the waveform, sized to sit inside the 44 pt drop.
    ///
    /// This 8 is the band's ONE rhythm, horizontal and vertical alike
    /// (`expandedGap`, `expandedSectionGap`), against the 10 the card and the
    /// classic block declare for theirs. Tighter because width is the scarce axis
    /// here: the slit is 185 pt at the default scale mode and ~125 at the
    /// narrowest, so every point spent on a gap comes out of the title column,
    /// whose floor NotchWidthBudgetTests pins. Three names because there are three
    /// sites, not three rhythms — moving one alone is how the drift comes back.
    static let compactGap: CGFloat = 8
    static let compactArtworkSide: CGFloat = 26
    static let compactArtworkRadius: CGFloat = 6
    /// The HUD row's gap (glyph | slider) — the exception to the rhythm above, and
    /// the same 10 the card's slider row uses: this row has two elements and no
    /// title column to protect, so the air costs nothing that is scarce.
    static let hudGap: CGFloat = 10
    /// Fixed column for that leading glyph — the shared indicator's column, read
    /// from it rather than re-declared: both skins draw the same icon-beside-bar
    /// row, and the column is what holds the bar still while the volume family
    /// steps through four symbols of different widths (HUDPresentation).
    static let hudIconColumnWidth: CGFloat = CardHUDIndicator.hudIconColumnWidth
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

    /// Artwork stays small so the title column keeps 117 pt of the 185 pt slit
    /// (185 − 24 padding − 36 cover − 8 gap) at the default scale mode, and 57 pt
    /// at the narrowest one, which NotchWidthBudgetTests floors — a 44 pt cover
    /// truncated most real titles.
    static let expandedArtworkSide: CGFloat = 36
    static let expandedArtworkRadius: CGFloat = 9
    static let expandedPaddingHorizontal: CGFloat = 12
    static let expandedPaddingVertical: CGFloat = 12
    /// The expanded header row (artwork | text), on the band's rhythm (compactGap).
    static let expandedGap: CGFloat = 8
    /// Between the expanded sections — the same rhythm, vertically.
    static let expandedSectionGap: CGFloat = 8
    /// Row heights are their content's OWN numbers, read from the types that own
    /// them: a re-declared 16 or 28 here would let the derived drop keep promising
    /// a height the scrubber or the transport block no longer has.
    static let scrubberRowHeight: CGFloat = CapsuleTrack.trackHitHeight
    static let controlsHeight: CGFloat = TransportControls.buttonSide
    /// Tighter than the transport's default 10: the band's width scales with
    /// the display's scale mode (the physical cutout is constant), and at the
    /// narrowest 14" mode (1024 pt wide) the content width is ~101 pt — three
    /// 28 pt targets at 8 pt gaps (100 pt) fit; at 10 they overflow the
    /// padding. NotchWidthBudgetTests pins this.
    static let controlsSpacing: CGFloat = 8
    /// The section view-only removes from the expanded drop: the transport row
    /// plus the gap above it — the band shrinks to the visible sections.
    static let controlsSectionHeight: CGFloat = expandedSectionGap + controlsHeight

    /// Corner radii of the surface outline: the base
    /// flares more than the top ("dripping from the notch"), and the surface
    /// opens into wider radii. Top/bottom, in points.
    static let compactTopRadius: CGFloat = 6
    static let compactBottomRadius: CGFloat = 14
    static let expandedTopRadius: CGFloat = 19
    static let expandedBottomRadius: CGFloat = 24
}
