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

    // MARK: - The card, expanded

    /// Narrower than collapsed, because the cover left: the words centre in a
    /// card that no longer has to hold a 50 pt square beside them.
    static let expandedCardWidth: CGFloat = 300

    static var expandedCardHeight: CGFloat {
        padding + textBlockHeight + gap + scrubberHeight + gap + transportSide + padding
    }

    static var expandedCardSize: CGSize {
        CGSize(width: expandedCardWidth, height: expandedCardHeight)
    }

    /// The cover, once it has left the card and taken the middle of the screen.
    static let heroSide: CGFloat = 300
    static let heroRadius: CGFloat = 24

    // MARK: - Placement

    /// How far the card floats above the bottom of the display. Above the
    /// avatar and the password field, which own the middle and the low centre.
    static let bottomInset: CGFloat = 96

    /// The blurred backdrop's radius and how far past the screen it is scaled,
    /// so a drifting image never exposes an edge.
    static let backdropBlur: CGFloat = 46
    static let backdropOverscan: CGFloat = 1.35
}
