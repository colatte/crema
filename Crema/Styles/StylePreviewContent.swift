import CoreGraphics

/// How a surface arranges the little a preview can show of a track: the cover,
/// and the title lines beside or under it.
///
/// Named by the skin rather than measured off the drawing. A rule that read the
/// drawn rect's proportions would flip a miniature the day a calibration moved a
/// few points — silently picturing a layout the app never renders.
enum PreviewContentArrangement: Equatable {
    /// A square cover on the leading edge, the track's two lines beside it: the
    /// skins that live along the top edge, whose surfaces are strips.
    case coverBesideTwoLines
    /// A square cover with one line under it, both centred: the classic block,
    /// which is nearly square and stacks what it holds.
    case coverAboveOneLine
}

/// Where the miniature content goes inside a preview surface, in the points of
/// whatever is drawing it.
///
/// Pure, so the tile is pinned by tests instead of by eye: the shipping tile draws
/// the notch's surface at 13.2 by 10.9 pt, where "looks right" is not a check
/// anyone can repeat. The caller hands in the surface it has already placed, and
/// gets back rects in that same space.
///
/// There is deliberately no waveform here. The real surfaces draw one; the
/// miniature does not, because at this size it is noise competing with the one
/// thing a tile exists to compare — where each skin PUTS its surface. The absence
/// is structural: a field nobody can fill is a decision that cannot be undone by
/// accident.
enum StylePreviewContent {
    /// The rects to draw, all of them inside the surface handed in.
    struct Layout: Equatable {
        let cover: CGRect
        /// The title first, the shorter line under it — a track's two lines in
        /// reading order, so a drawing can style them by position.
        let titleLines: [CGRect]
    }

    /// The content of one surface, or nil when there is no room to draw it
    /// legibly.
    static func layout(in surface: CGRect, arrangement: PreviewContentArrangement) -> Layout? {
        // Inset by hand rather than `insetBy`, which answers CGRect.null once the
        // inset outgrows the rect: null's infinities would make every comparison
        // below quietly false instead of obviously wrong.
        let content = CGRect(
            x: surface.minX + inset,
            y: surface.minY + inset,
            width: surface.width - 2 * inset,
            height: surface.height - 2 * inset
        )
        // Read off the stored size rather than `width`/`height`: those standardize,
        // so a rect turned inside out by the subtraction above reports a healthy
        // positive extent and every measurement taken after it belongs to a
        // rectangle nobody drew.
        guard content.size.width > 0, content.size.height > 0 else { return nil }
        let layout = switch arrangement {
        case .coverBesideTwoLines: beside(in: content)
        case .coverAboveOneLine: above(in: content)
        }
        return legible(layout) ? layout : nil
    }

    /// Cover on the leading edge, two lines beside it. A line, and the gap between
    /// the two, are each a third of the cover — so the text block is exactly as
    /// tall as the cover and the two centre together without a second calculation.
    private static func beside(in content: CGRect) -> Layout {
        let coverSide = min(content.height, content.width * coverWidthShare)
        let top = content.minY + (content.height - coverSide) / 2
        let lineHeight = coverSide / 3
        let linesX = content.minX + coverSide + inset
        let linesWidth = content.maxX - linesX
        return Layout(
            cover: CGRect(x: content.minX, y: top, width: coverSide, height: coverSide),
            titleLines: [
                CGRect(x: linesX, y: top, width: linesWidth, height: lineHeight),
                CGRect(x: linesX, y: top + 2 * lineHeight, width: linesWidth * shortLineWidthShare, height: lineHeight),
            ]
        )
    }

    /// Cover above one line, both centred. Same rhythm read the other way: cover,
    /// gap, and a line that is a third of the cover fill the height, so four thirds
    /// of the cover take whatever the gap leaves — and the cover is never wider
    /// than the block that holds it.
    private static func above(in content: CGRect) -> Layout {
        let coverSide = min(content.width, (content.height - inset) * 3 / 4)
        let lineHeight = coverSide / 3
        let top = content.minY + (content.height - (coverSide + inset + lineHeight)) / 2
        let left = content.midX - coverSide / 2
        return Layout(
            cover: CGRect(x: left, y: top, width: coverSide, height: coverSide),
            titleLines: [
                CGRect(x: left, y: top + coverSide + inset, width: coverSide, height: lineHeight),
            ]
        )
    }

    /// Nothing under its floor is drawn at all. Refusing the whole layout rather
    /// than clamping one rect is the point: a line clamped back up to its floor
    /// would grow into the cover it was placed beside, and a picture that
    /// misdescribes a skin is worse than one showing only its silhouette.
    ///
    /// Measured on the stored sizes for the same reason the content rect is: a line
    /// with no room left comes out backwards, and `width` would report its length
    /// as if it had been standardized — legible, according to a rect drawn in
    /// reverse.
    private static func legible(_ layout: Layout) -> Bool {
        guard layout.cover.size.width >= minCoverSide, layout.cover.size.height >= minCoverSide else { return false }
        return layout.titleLines.allSatisfy { $0.size.width >= minLineHeight && $0.size.height >= minLineHeight }
    }

    /// Margin between the surface's edge and everything in it, and the gap between
    /// the cover and what sits beside or under it — one number, because at this
    /// size a second one would be a difference nobody could see.
    ///
    /// A point value rather than a ratio, like the tile's other floors: what it
    /// defends is that the content reads as being INSIDE a surface instead of
    /// painted onto its edge. Raising it is not free, and the notch is the tile
    /// that pays: its drawn surface is 13.2 by 10.9 pt, so at 2 pt of margin a
    /// legible cover leaves 1.7 pt beside it, the second line comes to 0.9, and the
    /// flagship tile comes back empty (measured against the shipping 108 pt tile).
    private static let inset: CGFloat = 1

    /// The smallest square that still reads as artwork rather than a speck.
    private static let minCoverSide: CGFloat = 5

    /// The smallest a title line may be — on its LENGTH as much as its thickness,
    /// because a line as short as it is thin is a dot, and dots are the dust the
    /// nil return exists to refuse. It binds where the cover's floor cannot: on a
    /// narrow surface the cover clears 5 pt by taking most of the width, and what
    /// is left beside it is the thing that vanishes.
    private static let minLineHeight: CGFloat = 1.5

    /// The most of the inner width the cover may take. It is otherwise as tall as
    /// the surface allows, and these surfaces are small and nearly square (the
    /// notch's is 13.2 by 10.9 pt drawn), so a cover as wide as it is tall would
    /// leave a sliver where the text goes.
    private static let coverWidthShare: CGFloat = 0.6

    /// The second line is the artist's, and shorter — the shape of a track's two
    /// lines at a glance, which is the only thing anyone can read at this size.
    private static let shortLineWidthShare: CGFloat = 0.55
}
