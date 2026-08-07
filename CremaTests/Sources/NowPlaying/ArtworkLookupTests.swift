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

    private static let oneResult = Data("""
    {"resultCount":1,"results":[{"artworkUrl100":"https://x/100x100bb.jpg"}]}
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
        let noArt = Data(#"{"resultCount":1,"results":[{}]}"#.utf8)
        let result = await lookup { _ in noArt }
            .highResolutionArtwork(title: "Algernon", artist: nil, album: nil)
        #expect(result == nil)
    }
}
