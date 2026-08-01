import Testing
@testable import Crema

/// The menu's status row and the transport gate as one value: three shapes and the
/// predicate that follows from them, pinned without a view, because two of the
/// merges are defects the user sees — a dangling separator and a blank menu row —
/// and the third is an enabled Pause over "Nothing playing".
struct NowPlayingMenuLineTests {

    @Test func noMediaReadsAsNothing() {
        #expect(NowPlayingMenuLine(title: nil, artist: nil) == .nothing)
        // An artist with no title is not something to name — the surface would show
        // nothing either, and the menu must not invent a different answer.
        #expect(NowPlayingMenuLine(title: nil, artist: "Pink Floyd") == .nothing)
    }

    @Test func aTitleWithoutAnArtistStandsAlone() {
        #expect(NowPlayingMenuLine(title: "Breathe", artist: nil) == .title("Breathe"))
        // The blank artist is the dangling-separator case: composing it would ship
        // "Breathe — ".
        #expect(NowPlayingMenuLine(title: "Breathe", artist: "") == .title("Breathe"))
    }

    @Test func bothNamesComposeOneRow() {
        #expect(
            NowPlayingMenuLine(title: "Breathe", artist: "Pink Floyd")
                == .titleAndArtist(title: "Breathe", artist: "Pink Floyd")
        )
    }

    @Test func anEmptyTitleNeverBecomesABlankRow() {
        #expect(NowPlayingMenuLine(title: "", artist: "Pink Floyd") == .nothing)
    }

    /// The gate and the row come off the same value on purpose: an empty title that
    /// reads as "Nothing playing" must not also read as commandable media, or the
    /// menu offers Pause over a row saying nothing is playing.
    @Test func onlyARealNameEnablesTheTransport() {
        #expect(!NowPlayingMenuLine(title: nil, artist: nil).namesMedia)
        #expect(!NowPlayingMenuLine(title: "", artist: "Pink Floyd").namesMedia)
        #expect(NowPlayingMenuLine(title: "Breathe", artist: nil).namesMedia)
        #expect(NowPlayingMenuLine(title: "Breathe", artist: "Pink Floyd").namesMedia)
    }

    /// The same predicate over the three SHAPES rather than over the inputs that
    /// build them, because it now decides whether the transport EXISTS: stopped
    /// media leaves the row alone in the block, so a case answering the wrong way
    /// hides three working buttons or ships three dead ones. Total on purpose — a
    /// fourth shape must come here and choose.
    @Test func everyShapeAnswersWhetherThereIsMediaToActOn() {
        #expect(!NowPlayingMenuLine.nothing.namesMedia)
        #expect(NowPlayingMenuLine.title("Breathe").namesMedia)
        #expect(NowPlayingMenuLine.titleAndArtist(title: "Breathe", artist: "Pink Floyd").namesMedia)
    }
}
