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
/// The clock (`LockClockView`) is outside that rule rather than excepted from
/// it, and the distinction is the whole justification. The ramp exists so the
/// skins read as siblings; the clock has no sibling in any skin, because it is
/// not part of the family's vocabulary at all — it stands in for system UI that
/// this surface covered, and it appears on no other. It still refuses a pt
/// literal and takes semantic steps (`.title` over `.title3`), so it moves with
/// the system's own type rather than freezing a size somebody liked once.
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
    /// That was the first design. Cover (300) + gap + card (152) is 464 pt tall
    /// and, centred on the author's 982 pt panel, spans 259…723 — so its TOP
    /// leaves 641, the ceiling the ruler proved, and puts a large picture where
    /// nobody has looked. One tile is 300 and centres to 341…641, which is
    /// exactly the rectangle that was measured clear.
    ///
    /// This paragraph used to say the stack's BOTTOM landed back on the login,
    /// and that was arithmetic on a 900 pt display and a login top of 250 that
    /// the ruler never produced. Measured 2026-08-08: the login's top is at or
    /// below 180, so the stack cleared it by 79 pt. The sentence is corrected
    /// rather than deleted because the wrong version is the kind a reader
    /// reconstructs from memory.
    ///
    /// The interaction reason never depended on any of that, and it is the
    /// stronger one. Only the drawn surface takes a click here
    /// (`LockWidgetClickThrough`), so with the controls on the cover the cover IS
    /// the surface — where a separate hero above a card was a large picture that
    /// deliberately ignored every click aimed at it.
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
    /// Re-measured 2026-08-08, which is what turned a defensible guess into a
    /// number with room to spare. The first run proved only the centred square
    /// clear (341…641 on this panel), so 300 looked like it sat 41 pt BELOW the
    /// only proven ground. The second run read candidate B clear at 220 and put
    /// the login's top at or below 180 — so this clears the login by at least
    /// 120 pt and sits inside a band proven from 220 up.
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

    /// How tall the backdrop's fade is, sitting on top of `clearBandFloor`.
    ///
    /// The backdrop takes the whole display, which means it also covers the
    /// clock, the avatar and the password field. It clears the strip the login
    /// owns, and the boundary of that strip is `clearBandFloor` — the SAME
    /// measured number the card refuses to cross, not a second spelling of it.
    /// A hard edge there reads as a rendering bug, so the alpha ramps over this
    /// band above it.
    ///
    /// TASTE, and the only number here that is. The author asked for the fade to
    /// finish around half the height: 300 + 180 = 480, which on the 1512×982
    /// panel this was designed against is 51.1% from the top. Recorded as the
    /// arithmetic rather than as the fraction, because a fraction in the code
    /// would be a second answer to "where does the login begin" that diverges
    /// from the first on every display of a different height (they cross at
    /// 1071 pt and are ~100 pt apart on a 27-inch).
    static let backdropFadeBand: CGFloat = 180

    /// How far below the PHYSICAL top of the display the clock sits. Measured
    /// rather than assumed: a borderless screen-sized `NSHostingView` reports a
    /// `safeAreaInsets` of 0 even on a notched 1512x982 panel (macOS 26.6), so
    /// this already denotes the physical top. The `ignoresSafeArea` on the layer
    /// that carries it is belt-and-braces for a window that someday does get an
    /// inset — not, as this comment once claimed, the thing making the number
    /// mean what it says.
    ///
    /// Taste, with one floor that is not: it has to clear the notch. The deepest
    /// slit this repo has measured is 32 pt (`StylePreview.notchedReference`'s
    /// `safeTop`, and `NSScreen.safeAreaInsets.top` on the author's 14-inch
    /// reads the same), so anything at or under that would put the time inside
    /// the cutout on exactly the Macs the app was written for.
    static let clockTopInset: CGFloat = 88
}
