import CoreGraphics
import SwiftUI

/// Classic skin: the pre-Tahoe macOS HUD block, modernized — a rounded square
/// centered near the bottom of the screen (where the native OSD always lived;
/// design-reference §4.4), deliberately contrasting the top-edge styles. All
/// states share the bottom line and grow upward.
struct ClassicStyle: PresentationStyle {
    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        let size: CGSize
        switch state {
        case .hidden:
            // Zero-sized on the anchor line, so show/hide converges there.
            size = .zero
        case .nowPlaying(_, expanded: false):
            size = ClassicMetrics.compact
        case .nowPlaying(_, expanded: true):
            size = ClassicMetrics.expanded
        case .hud:
            size = ClassicMetrics.hud
        }
        return CGRect(
            x: geometry.frame.midX - size.width / 2,
            y: geometry.frame.minY + ClassicMetrics.bottomMargin,
            width: size.width,
            height: size.height
        )
    }

    /// Bottom-anchored, so the headroom goes sideways and up — the default
    /// (top-pinned) would let the open spring's overshoot clip at the top edge
    /// and would shift the anchor line.
    func windowFrame(on geometry: ScreenGeometry) -> CGRect {
        var rect = frame(
            for: .nowPlaying(NowPlaying(title: "", isPlaying: true, position: 0), expanded: true),
            on: geometry
        )
        rect.origin.x -= SurfaceAnimation.overshootHeadroom
        rect.size.width += 2 * SurfaceAnimation.overshootHeadroom
        rect.size.height += SurfaceAnimation.overshootHeadroom
        return rect
    }

    @MainActor
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> ClassicView {
        ClassicView(coordinator: coordinator, displayPolicy: displayPolicy)
    }
}

/// The classic block's measurements — one place, calibrated from the native
/// OSD's reverse-engineered values (design-reference §4.4: 200×200 at 140 pt
/// from the bottom, radius 16–19).
enum ClassicMetrics {
    static let bottomMargin: CGFloat = 140
    static let compact = CGSize(width: 170, height: 170)
    /// Derived like the card's: the block is the exact sum of its centered
    /// sections (artwork, stacked text, thin scrubber, transport), so no dead
    /// band can appear inside it — and it stays roughly square, the classic
    /// identity.
    static var expanded: CGSize {
        CGSize(
            width: 230,
            height: contentPadding * 2
                + expandedArtworkSide
                + contentGap
                + textStackHeight
                + contentGap
                + scrubberRowHeight
                + contentGap
                + controlsHeight
        )
    }

    static let hud = CGSize(width: 200, height: 200)
    /// One generous fixed radius for every state — the block is never low
    /// enough for a capsule to make sense.
    static let cornerRadius: CGFloat = 18

    /// 80 keeps the compact content (artwork + two text lines + waveform)
    /// within the block's padded height — 96 overflowed and collapsed the
    /// vertical padding.
    static let compactArtworkSide: CGFloat = 80
    /// Cover radii sit squarer than the floating skins' (~0.15 of the side vs
    /// their ~0.25): the cover follows the block's own 18 pt radius language —
    /// part of the bezel identity, not a missed calibration.
    static let compactArtworkRadius: CGFloat = 12
    /// The anchor without dominance: 88 keeps the artwork at ~⅓ of the block
    /// (140 ate half of it and pushed everything else together).
    static let expandedArtworkSide: CGFloat = 88
    static let expandedArtworkRadius: CGFloat = 14
    static let hudIconSize: CGFloat = 56
    static let contentPadding: CGFloat = 16
    /// Compact stack gap (artwork / text / waveform).
    static let compactGap: CGFloat = 8
    /// The HUD breathes wider than the media states: a lone glyph over the
    /// segmented track wants more air than the packed media block.
    static let hudPadding: CGFloat = contentPadding + 8
    /// One gap between the expanded sections — the block reads as one rhythm.
    static let contentGap: CGFloat = 10
    /// Fixed row heights so the section sum above is honest; the text row fits
    /// the shared two-line stack.
    static let textStackHeight: CGFloat = 30
    static let scrubberRowHeight: CGFloat = 16
    static let controlsHeight: CGFloat = 28
    /// The section view-only removes from the expanded height: the transport row
    /// plus the gap above it — the surface shrinks to the visible sections.
    static let controlsSectionHeight: CGFloat = contentGap + controlsHeight
}
