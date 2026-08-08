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
///
/// This file once carried a backdrop's four numbers and an expanded tile's
/// four more (docs/DECISIONS.md: the-lock-surface-is-a-card). They left in two
/// rounds for one reason: each was a way of making the surface larger, and each
/// bought its size with a cost somewhere else — a clock the backdrop obliged, a
/// centred geometry that reached the login on a short panel. What survives is
/// the geometry of ONE bounded object.
enum LockWidgetMetrics {

    // MARK: - The card, collapsed

    static let cardWidth: CGFloat = 340
    static let cornerRadius: CGFloat = 22
    static let padding: CGFloat = 16
    /// Between the cover and the words, and between each stacked row.
    static let gap: CGFloat = 12

    static let thumbnailSide: CGFloat = 50

    /// CONCENTRIC, not chosen: `inner = outer − padding`, which is 22 − 16.
    ///
    /// Apple states the rule and its worked example is literally this card —
    /// "one place this often shows up in is nested containers, like artwork in a
    /// card" (WWDC25 session 356). The API that computes it (`ConcentricRectangle`,
    /// `.containerConcentric`) is macOS 26, but the arithmetic needs no API.
    ///
    /// It shipped at 9 for a week, which is 3 pt over-round, and the reason it
    /// matters at the distance this surface is read from is that concentricity is
    /// a SILHOUETTE property: it keeps the gap between cover and card edge
    /// optically constant as it turns the corner, and a non-concentric pair makes
    /// that gap pinch — a misalignment the eye registers and cannot name, and one
    /// of the few cues still legible after the text has stopped resolving.
    ///
    /// If either number above moves, this one moves with it.
    static let thumbnailRadius: CGFloat = cornerRadius - padding

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
    /// Re-measured 2026-08-08, which is what turned a defensible guess into a
    /// number with room to spare. The first run proved only the centred square
    /// clear (341…641 on this panel), so 300 looked like it sat 41 pt BELOW the
    /// only proven ground. The second run read candidate B clear at 220 and put
    /// the login's top at or below 180 — so this clears the login by at least
    /// 120 pt and sits inside a band proven from 220 up.
    ///
    /// When to distrust it: a macOS that moves the login again. The signal is
    /// visible — re-run the ruler.
    ///
    /// The name now overstates what it does, and it is kept for the history the
    /// comment above carries. There is no band to clear any more: nothing is
    /// drawn below this line because nothing is drawn as a ground at all. What
    /// survives is the ONE job the number always really had — the floor the two
    /// bounded objects rest on and never cross.
    static let clearBandFloor: CGFloat = 300

    /// Collapsed, the surface rests on the floor of the clear band, which keeps
    /// the "card near the bottom" reading it was designed with while clearing
    /// the login by construction.
    static let bottomInset: CGFloat = clearBandFloor
}
