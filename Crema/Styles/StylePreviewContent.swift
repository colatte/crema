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
/// the notch's surface at 26.4 by 14.7 pt, where "looks right" is not a check
/// anyone can repeat. The caller hands in the surface it has already placed, and
/// gets back rects in that same space.
///
/// The content deliberately does NOT fill the surface. The first cut let the
/// cover take the whole inner height, and the owner's field verdict was that the
/// tiles read as stuffed — the furniture is punctuation, and what makes a surface
/// read as a SURFACE is the air around what it holds. Hence the proportional air
/// and the cover capped well under the height, below.
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
        // The strip skins breathe proportionally — a fixed margin that reads as
        // air on a 12 pt surface reads as a seam on a 15 pt one — with the fixed
        // value as the floor for surfaces too small to afford the share. The
        // block keeps the fixed margin: its cover is capped against the height
        // below, so the air is already in the cap.
        let air = switch arrangement {
        case .coverBesideTwoLines: max(inset, surface.height * airShare)
        case .coverAboveOneLine: inset
        }
        // Inset by hand rather than `insetBy`, which answers CGRect.null once the
        // inset outgrows the rect: null's infinities would make every comparison
        // below quietly false instead of obviously wrong.
        let content = CGRect(
            x: surface.minX + air,
            y: surface.minY + air,
            width: surface.width - 2 * air,
            height: surface.height - 2 * air
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

    /// Cover on the leading edge, two lines beside it. The cover takes seven
    /// tenths of the inner height — about 45% of the surface once the air is
    /// counted, the proportion the approved drawing carries — and a line, and the
    /// gap between the two, are each a third of the cover, so the text block is
    /// exactly as tall as the cover and the two centre together without a second
    /// calculation. The lines stop short of the trailing edge on purpose: text
    /// that touches the wall is what made the first cut read as stuffed.
    private static func beside(in content: CGRect) -> Layout {
        let coverSide = min(content.height * coverHeightShare, content.width * coverWidthShare)
        let top = content.minY + (content.height - coverSide) / 2
        let lineHeight = coverSide / 3
        let linesX = content.minX + coverSide + lineHeight
        let room = content.maxX - linesX
        return Layout(
            cover: CGRect(x: content.minX, y: top, width: coverSide, height: coverSide),
            titleLines: [
                CGRect(x: linesX, y: top, width: room * titleLineWidthShare, height: lineHeight),
                CGRect(x: linesX, y: top + 2 * lineHeight, width: room * shortLineWidthShare, height: lineHeight),
            ]
        )
    }

    /// Cover above one line, both centred. The cover is capped against the height
    /// as well as the width — the block is nearly square, so uncapped it swallows
    /// the surface it sits in — and the line under it keeps the third-of-cover
    /// rhythm the other arrangement uses.
    private static func above(in content: CGRect) -> Layout {
        let coverSide = min(content.width, (content.height - inset) * verticalCoverShare)
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

    /// The floor under the proportional air, and the block arrangement's whole
    /// margin. A point value rather than a ratio, like the tile's other floors:
    /// what it defends is that content on the smallest surfaces still reads as
    /// being INSIDE one instead of painted onto its edge.
    private static let inset: CGFloat = 1

    /// How much of a strip surface's height is air on each side. Proportional
    /// because the strips are magnified in the tile (26.4 by 14.7 pt for the
    /// notch, 40 by 12.3 for the card, against the shipping 108 pt tile): at
    /// those sizes a fixed point of margin lets the furniture crowd the walls,
    /// which is what the owner's field verdict called stuffed.
    private static let airShare: CGFloat = 0.18

    /// The most of the inner height the cover may take in the strip arrangement.
    /// Seven tenths of the content is ~45% of the surface once the air is
    /// counted — the cover as punctuation, never as filling.
    private static let coverHeightShare: CGFloat = 0.7

    /// The smallest square that still reads as artwork rather than a speck.
    private static let minCoverSide: CGFloat = 5

    /// The smallest a title line may be — on its LENGTH as much as its thickness,
    /// because a line as short as it is thin is a dot, and dots are the dust the
    /// nil return exists to refuse. It binds where the cover's floor cannot: on a
    /// narrow surface the cover clears 5 pt by taking most of the width, and what
    /// is left beside it is the thing that vanishes.
    private static let minLineHeight: CGFloat = 1.5

    /// The most of the inner width the cover may take, so a squat surface never
    /// trades the whole text block away for artwork.
    private static let coverWidthShare: CGFloat = 0.6

    /// How much of the room beside the cover the title takes. Under one, so even
    /// the longer line stops short of the trailing edge.
    private static let titleLineWidthShare: CGFloat = 0.78

    /// The second line is the artist's, and shorter — the shape of a track's two
    /// lines at a glance, which is the only thing anyone can read at this size.
    private static let shortLineWidthShare: CGFloat = 0.44

    /// The most of the inner height the block arrangement's cover may take,
    /// measured with the line and gap under it. Under the strip share on purpose:
    /// the block is the skin whose surface is tallest for its content, and the
    /// approved drawing keeps its cover under half the height.
    private static let verticalCoverShare: CGFloat = 0.55
}
