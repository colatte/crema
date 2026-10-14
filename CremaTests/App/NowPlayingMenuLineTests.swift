import Testing
@testable import Crema

/// The line naming the media, and with it whether the Now Playing section exists:
/// three shapes, pinned without a view, because merging any two is a defect the
/// user sees — a dangling separator ("Breathe — "), or a section built over a blank
/// row.
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
}
