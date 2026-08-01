import CoreGraphics
import Testing
@testable import Crema

/// The miniature a preview surface holds: a cover and the marks standing in for a
/// track's title lines. The rects are a few points across, so "looks right" is not
/// a check anyone can repeat — these pin what a person actually reads off the
/// tile, which is that something is INSIDE the surface, arranged the way that skin
/// arranges it, and that a surface with no room left shows nothing rather than
/// dust.
///
/// The fixtures are the surfaces the shipping tile really draws, measured rather
/// than invented: a 108 pt picture of a 1512 x 982 pt screen puts the 280 x 128 pt
/// card at 20.0 x 9.1 pt and the 230 x 224 pt classic block at 16.4 x 16.0. Retune
/// the tile or a skin's metrics and these have to be re-measured, not just re-run.
struct StylePreviewContentTests {

    /// A top-edge strip, at an origin away from zero on purpose: content placed in
    /// the tile's coordinates instead of the surface's would still land inside a
    /// rect that starts at the origin, and the picture would be wrong in the one
    /// way a test anchored at zero cannot see.
    private let strip = CGRect(x: 12, y: 7, width: 20, height: 9.1)
    /// The classic block, likewise offset.
    private let block = CGRect(x: 30, y: 21, width: 16.4, height: 16)

    @Test func theCoverIsASquareSetInsideTheSurface() throws {
        // Artwork is square, and it is INSIDE the surface: a cover drawn from the
        // surface's own corner reads as paint on the bezel rather than content in a
        // window, and one sized past the surface spills over the hairline that makes
        // the skin recognizable. Kills the missing inset and the overflowing cover.
        let layout = try #require(StylePreviewContent.layout(in: strip, arrangement: .coverBesideTwoLines))
        #expect(abs(layout.cover.width - layout.cover.height) < 0.0001, "the cover is square: \(layout.cover)")
        #expect(layout.cover.minX > strip.minX, "the cover clears the leading edge: \(layout.cover)")
        #expect(layout.cover.minY > strip.minY, "the cover clears the top edge: \(layout.cover)")
        #expect(layout.cover.maxX < strip.maxX, "the cover stays inside the surface: \(layout.cover)")
        #expect(layout.cover.maxY < strip.maxY, "the cover stays inside the surface: \(layout.cover)")
        #expect(layout.cover.midX < strip.midX, "the cover leads and the text follows it: \(layout.cover)")
    }

    @Test func theTwoLinesSitBesideTheCoverAndTheSecondIsShorter() throws {
        // A track reads as a picture with two lines next to it, the second shorter —
        // that shape is the whole content of the miniature. Kills the swapped
        // arrangement (which offers one line, not two), the reversed order (a long
        // line under a short one is not a title over an artist), and lines that
        // start inside the cover, which at this size is a smear rather than a layout.
        let layout = try #require(StylePreviewContent.layout(in: strip, arrangement: .coverBesideTwoLines))
        try #require(layout.titleLines.count == 2)
        let title = layout.titleLines[0]
        let artist = layout.titleLines[1]
        #expect(title.minX >= layout.cover.maxX, "the title clears the cover: \(title) against \(layout.cover)")
        #expect(artist.minX >= layout.cover.maxX, "the artist clears the cover: \(artist) against \(layout.cover)")
        #expect(artist.minY >= title.maxY, "the two lines stack in reading order: \(title), \(artist)")
        #expect(artist.width < title.width, "the second line is the shorter one: \(title), \(artist)")
        #expect(title.maxX <= strip.maxX && artist.maxX <= strip.maxX, "the lines stay inside the surface")
        #expect(title.minY >= strip.minY && artist.maxY <= strip.maxY, "the lines stay inside the surface")
    }

    @Test func theStackedArrangementCentresOneLineUnderTheCover() throws {
        // The classic block is nearly square, so its content stacks and centres —
        // the other half of what the two arrangements teach. Kills the collapse into
        // a single arrangement (which would put the cover on the leading edge with
        // two lines beside it) and a second line the block has no room for.
        let layout = try #require(StylePreviewContent.layout(in: block, arrangement: .coverAboveOneLine))
        try #require(layout.titleLines.count == 1)
        let line = layout.titleLines[0]
        #expect(abs(layout.cover.width - layout.cover.height) < 0.0001, "the cover is square: \(layout.cover)")
        #expect(line.minY >= layout.cover.maxY, "the line sits under the cover, not beside it: \(line)")
        #expect(abs(layout.cover.midX - block.midX) < 0.0001, "the cover is centred: \(layout.cover)")
        #expect(abs(line.midX - block.midX) < 0.0001, "the line is centred under it: \(line)")
        #expect(layout.cover.minY > block.minY, "the stack clears the top edge: \(layout.cover)")
        #expect(line.maxY < block.maxY, "the stack clears the bottom edge: \(line)")
    }

    @Test func aSurfaceWithNoRoomLeftDrawsNothingRatherThanDust() throws {
        // Both floors, each proved by the shape that trips it ALONE — a floor that
        // another one always reaches first is a guard no mutation can kill.
        //
        // Wide and short: 38 x 4.7 pt of room leaves lines that would read fine and a
        // cover of 4.7 pt, under the floor. Narrow and tall: a 5.4 pt cover clears its
        // floor and the title beside it is 2.6 pt long, but the shorter second line
        // comes to 1.4 pt, which is a fleck. Either way the answer is nothing: a
        // speck beside a fleck misdescribes the skin, and a tile that misdescribes is
        // worse than one showing only the silhouette.
        let tooShort = CGRect(x: 0, y: 0, width: 40, height: 6.7)
        let tooNarrow = CGRect(x: 0, y: 0, width: 11, height: 40)
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
            in: CGRect(x: 0, y: 0, width: 40, height: 7.2),
            arrangement: .coverBesideTwoLines
        ))
        #expect(short.cover.width >= 5 && short.cover.height >= 5, "the cover clears its floor: \(short.cover)")
        let narrow = try #require(StylePreviewContent.layout(
            in: CGRect(x: 0, y: 0, width: 12, height: 40),
            arrangement: .coverBesideTwoLines
        ))
        #expect(narrow.cover.width >= 5 && narrow.cover.height >= 5, "the cover clears its floor: \(narrow.cover)")
        for line in short.titleLines + narrow.titleLines {
            #expect(line.width >= 1.5 && line.height >= 1.5, "every line clears its floor: \(line)")
        }
    }
}
