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
            size = CardMetrics.hud
        }
        // Anchor below the safe area: on a notched display the card must not
        // sit behind the slit.
        return CGRect(
            x: geometry.frame.midX - size.width / 2,
            y: geometry.frame.maxY - geometry.safeTop - CardMetrics.topMargin - size.height,
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
    static let hud = CGSize(width: 260, height: 64)
    static let cornerRadius: CGFloat = 20

    static let compactArtworkSide: CGFloat = 40
    static let compactArtworkRadius: CGFloat = 10
    /// The artwork anchors the layout but must not dominate it (72 once ate
    /// half the card and left the rest floating in leftover space).
    static let expandedArtworkSide: CGFloat = 44
    static let expandedArtworkRadius: CGFloat = 10
    /// Fixed row heights so the section sum above is honest: the scrubber row
    /// centers the mini slider + time labels; the controls row is the transport
    /// block's hit target.
    static let scrubberRowHeight: CGFloat = 16
    static let controlsHeight: CGFloat = 28
    static let contentPaddingHorizontal: CGFloat = 16
    static let contentPaddingVertical: CGFloat = 10
    /// One gap for rows and stacks alike — the card reads as one rhythm.
    static let contentGap: CGFloat = 10
    /// The section view-only removes from the expanded height: the transport row
    /// plus the gap above it. Subtracting it lands the surface exactly on the
    /// visible sections (cover/text + scrubber) — the same "height is the sum of
    /// the sections" rule, now without the controls row.
    static let controlsSectionHeight: CGFloat = contentGap + controlsHeight
    /// Title-over-artist gap, shared by compact and expanded — the stacked
    /// text is the same element in both states.
    static let textStackSpacing: CGFloat = 2

    /// Decorative waveform — compact only: there it is the sole "playing"
    /// signal (no scrubber, no transport). Expanded already says it twice
    /// (scrubber motion + pause glyph), so the ornament stays out of it.
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
