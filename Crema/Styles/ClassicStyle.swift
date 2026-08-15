import CoreGraphics
import SwiftUI

/// Classic skin: the pre-Tahoe macOS HUD block, modernized — a rounded square
/// centered near the bottom of the screen (where the native OSD always
/// lived), deliberately contrasting the top-edge styles. All
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
    /// and would shift the anchor line. The anchor is the ONLY thing this
    /// overrides: the size still comes from the union of every state, exactly as
    /// the shared default builds it, because no single state is guaranteed
    /// largest on both axes. Sizing off the expanded block alone contained the
    /// 200² HUD by arithmetic coincidence (230 × 224 happens to cover it), and a
    /// coincidence is not a rule — the first state resize past it would clip the
    /// morph at the window edge, the artifact the fixed window exists to remove.
    func windowFrame(on geometry: ScreenGeometry) -> CGRect {
        let track = NowPlaying(title: "", isPlaying: true, position: 0)
        var rect = frame(for: .nowPlaying(track, expanded: true), on: geometry)
            .union(frame(for: .nowPlaying(track, expanded: false), on: geometry))
            .union(frame(for: .hud(SystemHUD(kind: .volume, value: 0)), on: geometry))
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
/// OSD's reverse-engineered values (200×200 at 140 pt from the bottom,
/// radius 16–19).
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
    /// Compact stack gap (artwork / text / waveform), and the only term in that
    /// stack with slack in it. The padded height is 170 − 2 × 16 = 138, and the
    /// stack is artwork 80 + gap + the two-line text + gap + the 12 pt waveform:
    /// measured at 137 with an 8 pt gap, which is one point from collapsing the
    /// vertical padding the way a 96 pt artwork once did. 7 buys back two, and
    /// the point it replaces was inside a line height's rounding — luck, not a
    /// margin. Re-do this sum before growing anything in the compact stack.
    static let compactGap: CGFloat = 7
    /// The HUD breathes wider than the media states: a lone glyph over the
    /// segmented track wants more air than the packed media block.
    static let hudPadding: CGFloat = contentPadding + 8
    /// One gap between the expanded sections — the block reads as one rhythm.
    static let contentGap: CGFloat = 10
    /// Fixed row heights so the section sum above is honest; the text row fits
    /// the shared two-line stack. The other two come from the components that
    /// fill them — the capsule's hit row and the transport's button — because a
    /// literal here is a second copy of a number that is retuned elsewhere, and
    /// the drift lands as dead space inside the derived block.
    static let textStackHeight: CGFloat = 30
    static let scrubberRowHeight: CGFloat = CapsuleTrack.trackHitHeight
    static let controlsHeight: CGFloat = TransportControls.buttonSide
    /// The section view-only removes from the expanded height: the transport row
    /// plus the gap above it — the surface shrinks to the visible sections.
    static let controlsSectionHeight: CGFloat = contentGap + controlsHeight
}
