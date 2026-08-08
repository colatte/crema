import Foundation
import Testing
@testable import Crema

/// The lookup, over an injected fetch — no network in any of these.
///
/// What a test can own here is the two pure parts (what gets asked, and how the
/// size is rewritten) and the failure behaviour, which is the whole contract:
/// every failure is silence, because the surface is already complete without an
/// answer.
struct ArtworkLookupTests {

    // MARK: - What gets asked

    @Test func theQueryCarriesAllThreeTerms() throws {
        let url = try #require(ITunesArtworkLookup.searchURL(
            title: "Algernon", artist: "Yorushika", album: "Algernon - Single"
        ))
        let term = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "term" }?.value)
        // The album is the reason `NowPlaying` grew a field: two terms match the
        // wrong single off a compilation often enough to matter.
        #expect(term.contains("Algernon"))
        #expect(term.contains("Yorushika"))
        #expect(term.contains("Single"))
    }

    @Test func missingTermsAreDroppedRatherThanSentEmpty() throws {
        // The JXA fallback has no album and often no artist. An empty term in
        // the query is not a narrower search, it is a worse one.
        let url = try #require(ITunesArtworkLookup.searchURL(title: "Algernon", artist: nil, album: ""))
        let term = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "term" }?.value)
        #expect(term == "Algernon")
    }

    @Test func nothingToSearchForMeansNoRequestAtAll() {
        #expect(ITunesArtworkLookup.searchURL(title: "", artist: nil, album: nil) == nil)
    }

    // MARK: - How the size is rewritten

    @Test func theSizeIsSubstitutedInThePath() throws {
        let small = "https://is1-ssl.mzstatic.com/image/thumb/Music116/v4/ba/eb/cc/x.jpg/100x100bb.jpg"
        let large = try #require(ITunesArtworkLookup.resized(small, to: 1200))
        #expect(large.absoluteString.hasSuffix("1200x1200bb.jpg"))
        #expect(!large.absoluteString.contains("100x100bb"))
    }

    @Test func anUnfamiliarURLShapeIsRefusedRatherThanGuessedAt() {
        // Guessing at a path this rewrite does not understand fetches a 404 at
        // best; refusing costs one silent miss.
        #expect(ITunesArtworkLookup.resized("https://example.com/cover.jpg", to: 1200) == nil)
    }

    @Test func theTargetIsOneTheEndpointActuallyServes() {
        // Measured against the real endpoint: 600, 1200 and 3000 resolve, above
        // 3000 is capped, and arbitrary sizes 404. 1200 covers a 300 pt hero at
        // 2x at a seventh of 3000's weight.
        #expect(ITunesArtworkLookup.targetPixelSize == 1200)
    }

    // MARK: - Failure is silence

    private func lookup(_ fetch: @escaping ITunesArtworkLookup.Fetch) -> ITunesArtworkLookup {
        ITunesArtworkLookup(fetch: fetch)
    }

    /// Shaped like the real endpoint's answer, which always names what it
    /// found. The names matter now: the lookup rejects a result that does not
    /// plausibly match the track it asked about (`ArtworkMatch`), so a fixture
    /// without them would be testing the rejection path by accident.
    private static let oneResult = Data("""
    {"resultCount":1,"results":[{"artworkUrl100":"https://x/100x100bb.jpg",
    "trackName":"Algernon","artistName":"Yorushika"}]}
    """.utf8)

    @Test func aMatchReturnsTheLargeBytes() async {
        let cover = Data(repeating: 0xAB, count: 20_000)
        let result = await lookup { url in
            url.absoluteString.contains("itunes.apple.com") ? Self.oneResult : cover
        }.highResolutionArtwork(title: "Algernon", artist: "Yorushika", album: nil)
        #expect(result?.count == 20_000)
    }

    @Test func aThrowingFetchIsSilence() async {
        struct Offline: Error {}
        let result = await lookup { _ in throw Offline() }
            .highResolutionArtwork(title: "Algernon", artist: nil, album: nil)
        // No network is the common case on a laptop that just woke, and it must
        // cost the widget nothing: it already has the player's own cover.
        #expect(result == nil)
    }

    @Test func noResultsIsSilence() async {
        let empty = Data(#"{"resultCount":0,"results":[]}"#.utf8)
        let result = await lookup { _ in empty }
            .highResolutionArtwork(title: "Something Unreleased", artist: nil, album: nil)
        #expect(result == nil)
    }

    @Test func aSuspiciouslySmallAnswerIsNotACover() async {
        // A redirect or an error page comes back as a couple of hundred bytes.
        // Handing that to the decoder yields a blank square where a cover was.
        let result = await lookup { url in
            url.absoluteString.contains("itunes.apple.com")
                ? Self.oneResult
                : Data(repeating: 0, count: 200)
        }.highResolutionArtwork(title: "Algernon", artist: nil, album: nil)
        #expect(result == nil)
    }

    @Test func aResultWithoutAnArtworkURLIsSilence() async {
        // A plausible match that simply carries no image — distinct from a
        // result that was rejected, which the match tests cover.
        let noArt = Data(#"{"resultCount":1,"results":[{"trackName":"Algernon"}]}"#.utf8)
        let result = await lookup { _ in noArt }
            .highResolutionArtwork(title: "Algernon", artist: nil, album: nil)
        #expect(result == nil)
    }
}

/// Whether a search result is the track that is playing.
///
/// The rule exists because `entity=song` guarantees every answer IS a song,
/// so the endpoint cheerfully returns one for a podcast episode. Taking the top
/// hit unchecked replaced correct artwork with an unrelated album cover — and
/// wrong art is worse than none, because the fallback was already right.
struct ArtworkMatchTests {

    @Test func aPodcastEpisodeIsNotMatchedByWhateverSongComesBack() {
        // The failure this exists for. Nothing about the two titles agrees, and
        // the check has to say so rather than hand over an album cover.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Ep. 412 — The Housing Crisis, Revisited",
            requestedArtist: "Search Engine",
            resultTitle: "Crisis",
            resultArtist: "Alice Deejay"
        ))
    }

    @Test func theSameRecordingSurvivesTheEndpointsExtraTail() {
        // Remasters, live versions and feature credits live in the parenthetical
        // tail, and they are the same cover often enough to keep. Rejecting them
        // would make the feature miss most of its real hits.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon",
            requestedArtist: "Yorushika",
            resultTitle: "Algernon (Remastered 2023)",
            resultArtist: "Yorushika"
        ))
        // And in the other direction: the player carries the tail, not Apple.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Breathe (In the Air)",
            requestedArtist: "Pink Floyd",
            resultTitle: "Breathe",
            resultArtist: "Pink Floyd"
        ))
    }

    @Test func caseAccentsAndPunctuationAreNotDisagreement() {
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Não Vá Embora",
            requestedArtist: "Tim Maia",
            resultTitle: "nao va embora",
            resultArtist: "TIM MAIA"
        ))
    }

    @Test func theRightSongByTheWrongArtistIsRefused() {
        // Covers and karaoke tracks are the common case, and they carry the
        // wrong art by definition.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Creep",
            requestedArtist: "Radiohead",
            resultTitle: "Creep",
            resultArtist: "Karaoke Kings"
        ))
    }

    @Test func aTrackWithNoArtistIsJudgedOnItsTitleAlone() {
        // The JXA fallback frequently reports no artist. Refusing every lookup
        // for those would turn a missing field into a missing feature.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: nil,
            resultTitle: "Algernon", resultArtist: "Yorushika"
        ))
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: "",
            resultTitle: "Algernon", resultArtist: "Yorushika"
        ))
    }

    @Test func anAnswerThatNamesNothingIsNoEvidence() {
        // A result with no trackName cannot be shown to agree with anything, and
        // absence must never read as assent.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: "Yorushika",
            resultTitle: nil, resultArtist: "Yorushika"
        ))
        // And a title that normalizes to nothing — punctuation only — must not
        // become an empty string that "contains" every other string.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "!!!", requestedArtist: nil,
            resultTitle: "Algernon", resultArtist: nil
        ))
    }

    @Test func theCheckRunsOnTheRealLookupAndNotJustInIsolation() async {
        // Wired, not merely written: the lookup must reject the response rather
        // than fetch its artwork.
        let podcast = Data("""
        {"resultCount":1,"results":[{"artworkUrl100":"https://x/100x100bb.jpg",
        "trackName":"Crisis","artistName":"Alice Deejay"}]}
        """.utf8)
        let asked = AskedForArtwork()
        let result = await ITunesArtworkLookup(fetch: { url in
            if !url.absoluteString.contains("itunes.apple.com") { asked.note() }
            return podcast
        }).highResolutionArtwork(
            title: "Ep. 412 — The Housing Crisis, Revisited", artist: "Search Engine", album: nil
        )
        #expect(result == nil)
        #expect(!asked.value, "a rejected match must not cost a second request")
    }
}

/// The fetch closure is `@Sendable`, so the flag it sets cannot be a captured
/// `var`. A tiny box under a lock says the same thing and crosses the boundary.
final class AskedForArtwork: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func note() { lock.withLock { flag = true } }
}

/// The hole a mutation opened up in the first version of `agrees`.
///
/// Plain containment accepted any short song title that appeared ANYWHERE in a
/// long one. The podcast case only failed because its artist disagreed too, so
/// the title check was carrying none of the weight it looked like it carried.
struct ArtworkMatchAnchoringTests {

    @Test func aSongTitleBuriedInsideALongerOneIsNotAMatch() {
        // The exact pair the mutation surfaced, minus the artist that was
        // secretly doing the work.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Ep. 412 — The Housing Crisis, Revisited",
            requestedArtist: nil,
            resultTitle: "Crisis",
            resultArtist: nil
        ))
    }

    @Test func aPrefixThatIsNotAWholeWordIsNotAMatch() {
        // "Love" must not match "Lovesong": different record, different art.
        #expect(!ArtworkMatch.agrees("Lovesong", "Love"))
        #expect(!ArtworkMatch.agrees("Love", "Lovesong"))
    }

    @Test func aTailIsStillTolerated() {
        // What containment was actually there for, and all of it survives.
        #expect(ArtworkMatch.agrees("Algernon", "Algernon feat. Someone"))
        #expect(ArtworkMatch.agrees("Algernon - Remastered", "Algernon"))
        #expect(ArtworkMatch.agrees("Breathe (In the Air)", "Breathe"))
    }
}
