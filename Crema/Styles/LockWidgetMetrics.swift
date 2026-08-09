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

    // MARK: - The card

    /// EVERY measure below is a multiple of this, and that is the point rather
    /// than a tidiness preference. The card read as five unrelated numbers —
    /// cover 72, text 38, transport 38, spacing 22, padding 16 — none derived
    /// from any other, and the author's word for the result was that nothing
    /// seemed to talk to anything. A module is what makes measures relate; the
    /// named relationships below are what makes the relation legible.
    ///
    /// The one deliberate exception is `TrackTextStack`'s 2 pt between title and
    /// artist, which belongs to the shared type ramp and is a WITHIN-group gap:
    /// it is supposed to be smaller than the module, or the pair stops reading
    /// as one object.
    static let unit: CGFloat = 4

    static let cardWidth: CGFloat = 95 * unit          // 380
    /// Bigger than it was, and the reason is arithmetic rather than taste: with
    /// a padding of 20 the concentric rule (`inner = outer − padding`) needs an
    /// outer of 28 to give the cover a radius of 8. At 22 the cover would have
    /// landed on 2 — visually square inside a very round card, which is the
    /// dissonance the concentric rule exists to prevent, arrived at by obeying
    /// it with the wrong parent.
    static let cornerRadius: CGFloat = 7 * unit        // 28

    /// THE GAP HIERARCHY, and it is the whole answer to "nothing talks".
    /// Padding is larger than the gap between rows, which is larger than the
    /// gap inside a row's own pair. Before this the card had 16 of padding
    /// against 12 of gap — near enough to equal that the three rows read as an
    /// undifferentiated stack rather than as three grouped things.
    static let padding: CGFloat = 5 * unit             // 20
    static let gap: CGFloat = 4 * unit                 // 16

    /// EXACTLY TWO PLAY BUTTONS. The cover was 72 because 72 hit a ratio; it is
    /// 80 because 80 is 2 × 40, and a size that is a multiple of another size on
    /// the same card is a size the eye can relate. It also lands the cover/card
    /// ratio at 38%, against the siblings measured this round (boring.notch 47%,
    /// FluentFlyout 67%) and the 33% this surface shipped with.
    static let thumbnailSide: CGFloat = 2 * transportPrimarySide   // 80

    /// CONCENTRIC: `inner = outer − padding`, Apple's rule, whose published
    /// worked example is literally artwork inside a card. 80/8 = 10.0 also sits
    /// mid-range against the siblings' size÷radius cluster (5.0 to 14.0), which
    /// is the sanity check the rule alone does not give.
    static let thumbnailRadius: CGFloat = cornerRadius - padding   // 8

    /// The source app's icon on the cover's corner. A quarter of the cover, so
    /// it stays a badge: bigger and it competes with the artwork it annotates.
    static let badgeSide: CGFloat = thumbnailSide / 4   // 20 — 5 × unit

    /// Taken from the scale rather than restated, so the two cannot drift.
    static let textBlockHeight: CGFloat = TrackTextStack.Scale.glance.blockHeight

    static let scrubberHeight: CGFloat = 4 * unit      // 16

    /// Two tiers, because three identical glyphs read as a row and two tiers
    /// read as a control. The skips keep a full hit target; what changes is
    /// which button the eye lands on first.
    static let transportSide: CGFloat = 7 * unit           // 28
    static let transportPrimarySide: CGFloat = 10 * unit   // 40
    static let transportSpacing: CGFloat = 7 * unit        // 28

    /// Tall enough for the cover or the words, whichever wins. Today the cover
    /// does; writing it as a max keeps that true if the ramp ever grows.
    static let headHeight: CGFloat = max(thumbnailSide, textBlockHeight)

    static var collapsedHeight: CGFloat {
        padding + headHeight + gap + scrubberHeight + gap + transportPrimarySide + padding
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
