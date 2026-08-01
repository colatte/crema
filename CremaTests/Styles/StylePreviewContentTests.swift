import CoreGraphics
import Testing
@testable import Crema

/// The miniature a preview surface holds: a cover and the marks standing in for a
/// track's title lines. The rects are a few points across, so "looks right" is not
/// a check anyone can repeat — these pin what a person actually reads off the
/// tile, which is that something sits INSIDE the surface with air around it,
/// arranged the way that skin arranges it, and that a surface with no room left
/// shows nothing rather than dust.
///
/// The fixtures are the surfaces the shipping tile really draws, measured rather
/// than invented: the tile magnifies its strip surfaces (`Thumbnail`'s boosts),
/// which puts the card at 40 x 12.3 pt and the notch at 26.4 x 14.7, while the
/// classic block stays faithful at 16.4 x 16.0. Retune the tile, the boosts or a
/// skin's metrics and these have to be re-measured, not just re-run.
///
/// Recalibrated 2026-08-01 with the owner's field verdict as the authorization:
/// the first cut let the cover fill the inner height and the tiles read as
/// stuffed, so the rule gained proportional air and capped covers — and every
/// number below was re-measured against that rule, not adjusted until green.
struct StylePreviewContentTests {

    /// A top-edge strip at the shipping card's magnified size, at an origin away
    /// from zero on purpose: content placed in the tile's coordinates instead of
    /// the surface's would still land inside a rect that starts at the origin, and
    /// the picture would be wrong in the one way a test anchored at zero cannot
    /// see.
    private let strip = CGRect(x: 12, y: 7, width: 40, height: 12.3)
    /// The classic block, likewise offset.
    private let block = CGRect(x: 30, y: 21, width: 16.4, height: 16)

    @Test func theCoverIsASquareSetInsideTheSurfaceWithProportionalAir() throws {
        // Artwork is square, INSIDE the surface, and the margin grows with the
        // surface: on this 12.3 pt strip the air comes to 2.21 pt, so a fixed
        // 1 pt margin — the airShare mutation — parks the cover against the wall
        // the field verdict already rejected. Kills the missing inset, the
        // overflowing cover, and the share collapsed to its floor.
        let layout = try #require(StylePreviewContent.layout(in: strip, arrangement: .coverBesideTwoLines))
        #expect(abs(layout.cover.width - layout.cover.height) < 0.0001, "the cover is square: \(layout.cover)")
        #expect(layout.cover.minX - strip.minX > 2, "the air is proportional, not the 1 pt floor: \(layout.cover)")
        #expect(layout.cover.minY > strip.minY, "the cover clears the top edge: \(layout.cover)")
        #expect(layout.cover.maxX < strip.maxX, "the cover stays inside the surface: \(layout.cover)")
        #expect(layout.cover.maxY < strip.maxY, "the cover stays inside the surface: \(layout.cover)")
        #expect(layout.cover.midX < strip.midX, "the cover leads and the text follows it: \(layout.cover)")
        // Punctuation, not filling: ~45% of the surface's height (5.51 of 12.3
        // measured). Letting it fill the inner height is the exact shape the
        // owner sent back. Kills coverHeightShare raised to fill.
        #expect(layout.cover.height < strip.height * 0.5, "the cover stays under half the height: \(layout.cover)")
    }

    @Test func theTwoLinesSitBesideTheCoverAndTheSecondIsShorter() throws {
        // A track reads as a picture with two lines next to it, the second shorter —
        // that shape is the whole content of the miniature. Kills the swapped
        // arrangement (which offers one line, not two), the reversed order (a long
        // line under a short one is not a title over an artist), lines that start
        // inside the cover, and a title stretched to the trailing wall — text that
        // touches the wall is what made the first cut read as stuffed.
        let layout = try #require(StylePreviewContent.layout(in: strip, arrangement: .coverBesideTwoLines))
        try #require(layout.titleLines.count == 2)
        let title = layout.titleLines[0]
        let artist = layout.titleLines[1]
        #expect(title.minX >= layout.cover.maxX, "the title clears the cover: \(title) against \(layout.cover)")
        #expect(artist.minX >= layout.cover.maxX, "the artist clears the cover: \(artist) against \(layout.cover)")
        #expect(artist.minY >= title.maxY, "the two lines stack in reading order: \(title), \(artist)")
        #expect(artist.width < title.width, "the second line is the shorter one: \(title), \(artist)")
        // Measured: the title ends at 43.6 on a strip whose content edge is 49.8.
        #expect(title.maxX < strip.maxX - 5, "the title stops short of the trailing edge: \(title)")
        #expect(title.minY >= strip.minY && artist.maxY <= strip.maxY, "the lines stay inside the surface")
    }

    @Test func theStackedArrangementCentresOneLineUnderTheCover() throws {
        // The classic block is nearly square, so its content stacks and centres —
        // the other half of what the two arrangements teach. Kills the collapse into
        // a single arrangement (which would put the cover on the leading edge with
        // two lines beside it), a second line the block has no room for, and the
        // vertical cap released — uncapped, the cover swallows the block it sits in.
        let layout = try #require(StylePreviewContent.layout(in: block, arrangement: .coverAboveOneLine))
        try #require(layout.titleLines.count == 1)
        let line = layout.titleLines[0]
        #expect(abs(layout.cover.width - layout.cover.height) < 0.0001, "the cover is square: \(layout.cover)")
        #expect(line.minY >= layout.cover.maxY, "the line sits under the cover, not beside it: \(line)")
        #expect(abs(layout.cover.midX - block.midX) < 0.0001, "the cover is centred: \(layout.cover)")
        #expect(abs(line.midX - block.midX) < 0.0001, "the line is centred under it: \(line)")
        #expect(layout.cover.minY > block.minY, "the stack clears the top edge: \(layout.cover)")
        #expect(line.maxY < block.maxY, "the stack clears the bottom edge: \(line)")
        // Measured 7.15 of 16: the block's cover keeps under half the height too.
        #expect(layout.cover.height < block.height * 0.5, "the cover is punctuation here as well: \(layout.cover)")
    }

    @Test func aSurfaceWithNoRoomLeftDrawsNothingRatherThanDust() throws {
        // Both floors, each proved by the shape that trips it ALONE — a floor that
        // another one always reaches first is a guard no mutation can kill.
        //
        // Wide and short: 40 x 10.9 pt leaves 6.98 pt of inner height, and seven
        // tenths of that is a 4.88 pt cover, under the floor, while the lines
        // beside it would read fine. Narrow and tall: on 14 x 12 the cover clears
        // its floor at 5.38 pt and the title beside it comes to 1.96, but the
        // shorter second line is 1.11 pt, which is a fleck. Either way the answer
        // is nothing: a speck beside a fleck misdescribes the skin, and a tile
        // that misdescribes is worse than one showing only the silhouette.
        let tooShort = CGRect(x: 0, y: 0, width: 40, height: 10.9)
        let tooNarrow = CGRect(x: 0, y: 0, width: 14, height: 12)
        #expect(StylePreviewContent.layout(in: tooShort, arrangement: .coverBesideTwoLines) == nil)
        #expect(StylePreviewContent.layout(in: tooNarrow, arrangement: .coverBesideTwoLines) == nil)
        // Degenerate input answers nil in both arrangements. Pinned as the
        // ANSWER, not as any one code path: the floors already reject the
        // negative rects the inset subtraction produces here, so the explicit
        // zero-size guard in `layout` is belt-and-braces these two lines cannot
        // isolate — deleting it leaves them green by the floors' verdict.
        #expect(StylePreviewContent.layout(in: .zero, arrangement: .coverBesideTwoLines) == nil)
        #expect(StylePreviewContent.layout(in: .zero, arrangement: .coverAboveOneLine) == nil)

        // The other half of a floor: just above it, real rects come back, and every
        // one of them clears the floor it was measured against. The numbers are
        // written out rather than read back from production — a floor that changes
        // has to be re-measured, not just re-run.
        let short = try #require(StylePreviewContent.layout(
            in: CGRect(x: 0, y: 0, width: 40, height: 11.4),
            arrangement: .coverBesideTwoLines
        ))
        #expect(short.cover.width >= 5 && short.cover.height >= 5, "the cover clears its floor: \(short.cover)")
        let narrow = try #require(StylePreviewContent.layout(
            in: CGRect(x: 0, y: 0, width: 16, height: 12),
            arrangement: .coverBesideTwoLines
        ))
        #expect(narrow.cover.width >= 5 && narrow.cover.height >= 5, "the cover clears its floor: \(narrow.cover)")
        for line in short.titleLines + narrow.titleLines {
            #expect(line.width >= 1.5 && line.height >= 1.5, "every line clears its floor: \(line)")
        }
    }
}
