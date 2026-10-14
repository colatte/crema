import CoreGraphics
import SwiftUI

/// Card skin: a generously rounded rectangle floating below the top edge, the
/// full now-playing player and the floating skin for displays without a notch.
/// Growth happens in height (compact strip → tall block) while the width hugs
/// the content between floor and ceiling — and it is never a capsule.
struct CardStyle: PresentationStyle {
    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
        let size: CGSize
        switch state {
        case .hidden:
            // Zero-sized on the anchor line, so show/hide converges there.
            size = .zero
        case .nowPlaying(_, expanded: false):
            size = CardMetrics.compact
        case .nowPlaying(_, expanded: true):
            size = CardMetrics.expanded
        case .hud:
            // On the card's own spot, where the HUD morphs from the now-playing
            // card.
            return Self.hudFrame(at: .topCenter, on: geometry)
        }
        return Self.topCentered(size, on: geometry)
    }

    /// The HUD at `placement` on this screen. Along the top edge it hangs from
    /// the card's own top anchor, below the safe area; along the bottom it sits
    /// `hudBottomMargin` up; on a side it keeps `hudSideMargin` from the edge and,
    /// in the middle of that side, stands upright (`HUDPlacement.axis`).
    static func hudFrame(at placement: HUDPlacement, on geometry: ScreenGeometry) -> CGRect {
        let size = CardMetrics.hudSize(for: placement.axis)
        let screen = geometry.frame
        let x: CGFloat = switch placement {
        case .topLeft, .middleLeft, .bottomLeft:
            screen.minX + CardMetrics.hudSideMargin
        case .topCenter, .bottomCenter:
            screen.midX - size.width / 2
        case .topRight, .middleRight, .bottomRight:
            screen.maxX - CardMetrics.hudSideMargin - size.width
        }
        let y: CGFloat = switch placement {
        case .topLeft, .topCenter, .topRight:
            topAnchor(on: geometry) - size.height
        case .middleLeft, .middleRight:
            screen.midY - size.height / 2
        case .bottomLeft, .bottomCenter, .bottomRight:
            screen.minY + CardMetrics.hudBottomMargin
        }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// The line every top-anchored Card surface hangs from: below the safe area,
    /// so on a notched display nothing sits behind the slit.
    private static func topAnchor(on geometry: ScreenGeometry) -> CGFloat {
        geometry.frame.maxY - geometry.safeTop - CardMetrics.topMargin
    }

    private static func topCentered(_ size: CGSize, on geometry: ScreenGeometry) -> CGRect {
        CGRect(
            x: geometry.frame.midX - size.width / 2,
            y: topAnchor(on: geometry) - size.height,
            width: size.width,
            height: size.height
        )
    }

    @MainActor
    func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> CardView {
        CardView(coordinator: coordinator, displayPolicy: displayPolicy)
    }
}

/// The card's measurements — one place. The growth axis is vertical and the
/// outline is a fixed-radius rounded rectangle. Compact and expanded hug
/// their content's width between a floor and a ceiling (HuggingWidthClamp);
/// the frame rule stays payload-independent — its widths are the ceilings
/// bounding hover and click regions.
enum CardMetrics {
    static let topMargin: CGFloat = 8
    /// Rule-frame compact size; the width doubles as the adaptive ceiling.
    static let compact = CGSize(width: 280, height: 64)
    static let compactMinWidth: CGFloat = 180
    static var compactMaxWidth: CGFloat { compact.width }
    /// Derived, not declared: the expanded height is the exact sum of its
    /// stacked sections (header, scrubber, controls, gaps, padding). Dead
    /// vertical space cannot reappear without a metric saying so — and
    /// resizing the card means deciding which section changes.
    static var expanded: CGSize {
        CGSize(
            width: expandedMaxWidth,
            height: contentPaddingVertical * 2
                + expandedArtworkSide
                + contentGap
                + scrubberRowHeight
                + contentGap
                + controlsHeight
        )
    }

    /// The floor keeps the spanning scrubber (with both time labels) usable
    /// when a short title would hug narrower.
    static let expandedMinWidth: CGFloat = 240
    static let expandedMaxWidth: CGFloat = 280
    /// Dedicated system-HUD frame, deliberately smaller than the now-playing
    /// compact strip: that strip is sized around a 40 pt artwork the HUD never
    /// shows, so reusing it leaves the volume/brightness bar oversized for
    /// glance-level info. Issue #3's reference indicators are thin
    /// bars, roughly 4.5–5.5:1 width:height; 210×42 (5:1) sits mid-range. Both
    /// Card HUD variants lay out in it: the .slider row is the icon column
    /// (CardHUDIndicator.hudIconSlot) beside the capsule's 16 pt hit row
    /// (CapsuleTrack.trackHitHeight) centered in the 42 pt height with headroom
    /// to spare, and the full-bleed .filled bar adapts by construction while its
    /// leading glyph stays legible at the shorter height. Width and height are
    /// separate calibration knobs.
    static let hudSystemWidth: CGFloat = 210
    static let hudSystemHeight: CGFloat = 42
    static let hudSystemSize = CGSize(width: hudSystemWidth, height: hudSystemHeight)

    /// The HUD's size as the bar runs: the strip above, or the same strip
    /// transposed when it stands upright — one size, never a second declaration.
    static func hudSize(for axis: Axis) -> CGSize {
        axis == .horizontal ? hudSystemSize : CGSize(width: hudSystemHeight, height: hudSystemWidth)
    }

    /// Distance from a side edge for a HUD placed on the screen's left or right.
    static let hudSideMargin: CGFloat = 16
    /// Distance from the bottom edge for a HUD placed along it: where macOS drew
    /// its own HUD, the native OSD's height that Classic reproduces — read from
    /// Classic, so the two bottom HUDs stand at one height. The Dock is not read
    /// (`ScreenGeometry` carries no visible frame): a Dock taller than this
    /// margin sits over a bottom HUD.
    static let hudBottomMargin: CGFloat = ClassicMetrics.bottomMargin
    /// Now-playing surface radius: generous, near half the compact height so the
    /// player reads as a soft block (never a capsule at its taller states).
    static let cornerRadius: CGFloat = 20
    /// HUD-state surface radius, a separate knob from cornerRadius: at the short
    /// 42 pt HUD height, reusing 20 (≈ half the height) rounds the ends into a
    /// capsule. Issue #3's reference indicators are rounded rectangles — soft
    /// corners with straight runs, radius ~1/4 of the height. This rides the same
    /// layoutKind-keyed surface spring, so HUD↔now-playing morphs the outline
    /// (RoundedRectangle cornerRadius is animatable) instead of snapping.
    static let hudSystemCornerRadius: CGFloat = 12

    /// Filled HUD indicator (HUDIndicatorStyle.filled): the whole card IS the
    /// bar. The fill sweeps edge to edge under the card's own corners with no
    /// inner track; the level is the boundary between a light fill and a dark
    /// remainder (iOS Control Center contrast), fixed across light and dark so
    /// the fill always reads and the empty stays recessed in both. No radius
    /// here — the card's rounded-rect clip rounds the sweep.
    static let hudFilledFill = Color.white.opacity(0.9)
    static let hudFilledEmpty = Color.black.opacity(0.55)
    /// Grayish glyph that stays legible over both the light fill and the dark
    /// remainder — at low levels the icon sits on the empty area.
    static let hudFilledIconColor = Color(white: 0.5)
    /// Inset of the icon riding inside the fused bar, from the bar's start —
    /// the leading edge, or the bottom of an upright bar. The bar is 42 pt thick
    /// either way, so the same inset puts the glyph past the 12 pt corner curve
    /// (hudSystemCornerRadius) in both orientations.
    static let hudFilledIconInset: CGFloat = 18

    static let compactArtworkSide: CGFloat = 40
    static let compactArtworkRadius: CGFloat = 10
    /// The artwork anchors the layout but must not dominate it (72 once ate
    /// half the card and left the rest floating in leftover space).
    static let expandedArtworkSide: CGFloat = 44
    static let expandedArtworkRadius: CGFloat = 10
    /// Fixed row heights so the section sum above is honest — and taken from the
    /// components that fill them, never re-declared: the scrubber row IS the
    /// capsule's hit row (the stock Slider's measured height, which the drag
    /// target may not regress below) and the controls row IS the transport's
    /// button. A literal here is a second copy that drifts the day either is
    /// retuned, and the drift shows up as dead space inside the derived surface.
    static let scrubberRowHeight: CGFloat = CapsuleTrack.trackHitHeight
    static let controlsHeight: CGFloat = TransportControls.buttonSide
    static let contentPaddingHorizontal: CGFloat = 16
    static let contentPaddingVertical: CGFloat = 10
    /// One gap for rows and stacks alike — the card reads as one rhythm.
    static let contentGap: CGFloat = 10
    /// The section view-only removes from the expanded height: the transport row
    /// plus the gap above it. Subtracting it lands the surface exactly on the
    /// visible sections (cover/text + scrubber) — the same "height is the sum of
    /// the sections" rule, now without the controls row.
    static let controlsSectionHeight: CGFloat = contentGap + controlsHeight
}
