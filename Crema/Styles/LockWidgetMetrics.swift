import CoreGraphics

/// Sizes for the lock-screen surface, as sums rather than as measured pixels:
/// dead vertical space cannot reappear without a metric saying so, the same
/// discipline `CardMetrics` and `ClassicMetrics` keep.
///
/// The card is wider than the Card skin's 280 pt because it has no work to
/// stay out of. The TYPE is not scaled up with it: `TrackTextStack` fixes one
/// ramp for the whole family so the skins read as siblings, and a lock surface
/// that set its own would be the first to break that for a feeling nobody
/// measured. The numbers below are Crema's own, derived here — none of them
/// came from another app's screenshot.
enum LockWidgetMetrics {

    // MARK: - The card, collapsed

    static let cardWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 16
    /// Between the cover and the words, and between each stacked row.
    static let gap: CGFloat = 12

    static let thumbnailSide: CGFloat = 50
    static let thumbnailRadius: CGFloat = 9

    /// `TrackTextStack`'s two lines at the family ramp — `.subheadline` over
    /// `.caption`, 2 pt apart. A reserved height rather than a measured one, so
    /// the card does not resize by a point when an artist is missing; if the
    /// ramp ever moves, this is the single number that moves with it.
    static let textBlockHeight: CGFloat = 34

    static let scrubberHeight: CGFloat = 16
    static let transportSide: CGFloat = 30
    static let transportSpacing: CGFloat = 22

    /// Tall enough for the cover or the words, whichever wins. Today the cover
    /// does; writing it as a max keeps that true if the ramp ever grows.
    static let headHeight: CGFloat = max(thumbnailSide, textBlockHeight)

    static var collapsedHeight: CGFloat {
        padding + headHeight + gap + scrubberHeight + gap + transportSide + padding
    }

    static var collapsedSize: CGSize {
        CGSize(width: cardWidth, height: collapsedHeight)
    }

    // MARK: - Expanded: one tile, not a stack

    /// Expanded, the surface is a SQUARE the size of the cover, with the words
    /// and the controls laid over its lower part — not the cover with a card
    /// beneath it.
    ///
    /// That was the first design and it does not fit. Cover (300) + gap + card
    /// (~152) is roughly 470 pt tall, and centring 470 pt on a 900 pt display
    /// puts its bottom edge at y≈214 — back inside the strip the login owns
    /// (`clearBandFloor`). One tile is 300 and centres to exactly 300…600, which
    /// is the band that was measured clear rather than assumed clear.
    ///
    /// It also settles the interaction. Only the drawn surface takes a click
    /// here (`LockWidgetClickThrough`), so with the controls on the cover the
    /// cover IS the surface — where a separate hero above a card was a large
    /// picture that deliberately ignored every click aimed at it.
    static let expandedSide: CGFloat = 300
    static let expandedRadius: CGFloat = 24

    static var expandedSize: CGSize {
        CGSize(width: expandedSide, height: expandedSide)
    }

    /// The scrim's share of the tile: enough for the two text lines, the
    /// scrubber and the transport row, plus the padding around them.
    static var expandedControlsHeight: CGFloat {
        textBlockHeight + gap + scrubberHeight + gap + transportSide + padding
    }

    // MARK: - Placement

    /// MEASURED, not chosen — and the distinction is why this comment is long.
    ///
    /// The card used to sit 96 pt up with a comment claiming that cleared "the
    /// avatar and the password field". It did not: macOS **Sonoma moved the
    /// login UI down**, clock to the top and user tile to the bottom section, so
    /// 96 pt is precisely where the password field now lives. Confirmed on
    /// hardware 2026-08-07 with `scripts/probes/lockscreen-geometry.swift`: a
    /// card at 96 pt lands on the avatar, while a 300 pt square centred on the
    /// display touches nothing.
    ///
    /// Two reasons this number is allowed to be a measurement at all. The app
    /// requires macOS 14+, and Sonoma IS the release that moved the login down —
    /// so every version in range shares this layout. And the axis that has moved
    /// between releases is the vertical one; horizontally the login has been
    /// centred in every version, which is why the surface can stay centred
    /// without a second thought.
    ///
    /// When to distrust it: a macOS that moves the login again. The signal is
    /// visible — re-run the ruler.
    static let clearBandFloor: CGFloat = 300

    /// Collapsed, the surface rests on the floor of the clear band, which keeps
    /// the "card near the bottom" reading it was designed with while clearing
    /// the login by construction.
    static let bottomInset: CGFloat = clearBandFloor

    /// The blurred backdrop's radius and how far past the screen it is scaled,
    /// so a drifting image never exposes an edge.
    static let backdropBlur: CGFloat = 46
    static let backdropOverscan: CGFloat = 1.35
}
