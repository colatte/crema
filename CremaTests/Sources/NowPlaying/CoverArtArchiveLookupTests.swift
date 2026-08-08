import Foundation
import Testing
@testable import Crema

/// The lookup over an injected fetch — no network in any of these.
///
/// What a test can own is the pure parts (what gets asked, and of whom), the
/// judgement about which answer is the record that is playing, and the failure
/// behaviour, which is the whole contract: every failure is silence, because the
/// surface is already complete without an answer.
struct CoverArtArchiveLookupTests {

    // MARK: - What gets asked, and of whom

    @Test func theAlbumPathAsksMusicBrainzForAReleaseGroup() throws {
        let url = try #require(CoverArtArchiveLookup.releaseGroupSearchURL(
            album: "The Dark Side of the Moon", artist: "Pink Floyd"
        ))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value)
        #expect(url.path.contains("/ws/2/release-group"))
        #expect(query == #"releasegroup:"The Dark Side of the Moon" AND artist:"Pink Floyd""#)
    }

    @Test func theGuessedPathAsksAboutTheRecordingInstead() throws {
        // A release group search on a track name finds nothing at all — measured
        // against the real endpoint before this path was written — so a player
        // that never said which record this came from needs a different question.
        let url = try #require(CoverArtArchiveLookup.recordingSearchURL(title: "Creep", artist: "Radiohead"))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value)
        #expect(url.path.contains("/ws/2/recording"))
        #expect(query == #"recording:"Creep" AND artist:"Radiohead""#)
    }

    @Test func anArtistNobodyReportedIsLeftOutRatherThanSentEmpty() throws {
        // An empty term is not a narrower search, it is a broken one: the
        // endpoint reads Lucene, and `artist:""` matches nothing.
        let url = try #require(CoverArtArchiveLookup.recordingSearchURL(title: "Algernon", artist: ""))
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "query" }?.value)
        #expect(query == #"recording:"Algernon""#)
    }

    @Test func aQuoteInATitleDoesNotEndTheQueryEarly() {
        // Bowie's "Heroes" is spelled with them, and unescaped the phrase closes
        // on the album's own punctuation — everything after it becomes query
        // syntax and the search either errors or matches the wrong record.
        #expect(CoverArtArchiveLookup.phrase(#""Heroes""#) == #""\"Heroes\"""#)
        #expect(CoverArtArchiveLookup.phrase(#"AC\DC"#) == #""AC\\DC""#)
    }

    @Test func nothingToSearchForMeansNoRequestAtAll() {
        #expect(CoverArtArchiveLookup.releaseGroupSearchURL(album: "", artist: "Pink Floyd") == nil)
        #expect(CoverArtArchiveLookup.recordingSearchURL(title: "", artist: nil) == nil)
    }

    @Test func theCoverURLNamesTheGroupAndTheSize() throws {
        let url = try #require(CoverArtArchiveLookup.coverURL(
            releaseGroup: "f5093c06-23e3-404f-aeaa-40f72885ee3a"
        ))
        #expect(url.absoluteString == "https://coverartarchive.org/release-group/"
            + "f5093c06-23e3-404f-aeaa-40f72885ee3a/front-1200")
    }

    @Test func theTargetIsOneTheArchiveActuallyServes() {
        // Measured against the real archive on a real release group: it serves
        // 250, 500 and 1200 as fixed sizes, and 1200 came back at 77 KB — enough
        // for a 300 pt hero at 2x on a surface that is decoration.
        #expect(CoverArtArchiveLookup.targetPixelSize == 1200)
    }

    @Test func theSpacingIsTheLimitMusicBrainzPublishes() {
        // One request per second per source IP, stated in their own docs. The
        // number is not a guess to be tuned; changing it is changing what the
        // app promises the service it is a guest of.
        #expect(CoverArtArchiveLookup.musicBrainzSpacing == 1)
    }

    @Test func theUserAgentNamesTheAppAndAWayToReachIt() {
        // MusicBrainz refuses a request that does not, which makes this the one
        // header whose absence turns the whole feature off.
        let agent = CoverArtArchiveLookup.defaultUserAgent(version: "1.4.0")
        #expect(agent == "Crema/1.4.0 ( https://github.com/colatte/crema )")
    }

    // MARK: - Which answer is the record that is playing

    /// The measurement this path exists because of, trimmed to its shape: eight
    /// live bootlegs rank above *Pablo Honey* for "Creep", every one of them a
    /// real release carrying real, wrong art.
    private static let creepRecordings = Data("""
    {"recordings":[{"title":"Creep","artist-credit":[{"name":"Radiohead"}],"releases":[
      {"release-group":{"id":"live-boston","title":"1996-08-14: Great Woods, Boston, MA, USA",
       "primary-type":"Album","secondary-types":["Live"]}},
      {"release-group":{"id":"live-paris","title":"1993-02-23: Black Session #21: Paris, France",
       "primary-type":"Album","secondary-types":["Live"]}},
      {"release-group":{"id":"pablo-honey","title":"Pablo Honey","primary-type":"Album"}}]}]}
    """.utf8)

    @Test func theStudioRecordWinsOverTheBootlegsThatOutrankIt() throws {
        let chosen = try CoverArtArchiveLookup.groups(
            fromRecordingSearch: Self.creepRecordings, title: "Creep", artist: "Radiohead"
        )
        // Not merely "pablo-honey is in there": it has to be the one taken, and
        // the bootlegs have to be gone. A filter that only reordered would leave
        // the next maintainer one ranking change away from a bootleg cover.
        #expect(chosen == ["pablo-honey"])
    }

    @Test func aRecordingByAnotherArtistIsRefusedBeforeItsTypeIsEvenLookedAt() throws {
        // The karaoke case, on the guessed path: an untyped studio release group
        // passes the secondary-type filter perfectly well, so the artist check is
        // the only thing standing between it and the screen.
        let chosen = try CoverArtArchiveLookup.groups(
            fromRecordingSearch: Self.creepRecordings, title: "Creep", artist: "Karaoke Kings"
        )
        #expect(chosen.isEmpty)
    }

    @Test func anAlbumTheUserIsPlayingKeepsItsOwnLiveCover() throws {
        // The asymmetry, and the reason the two paths are written differently:
        // the secondary-type filter exists to break a tie the app had to guess,
        // and there is no tie here. Someone playing a live record asked for the
        // live record.
        let live = Data("""
        {"release-groups":[{"id":"pompeii","title":"Live at Pompeii","primary-type":"Album",
          "secondary-types":["Live"],"artist-credit":[{"name":"Pink Floyd"}]}]}
        """.utf8)
        let chosen = try CoverArtArchiveLookup.groups(
            fromAlbumSearch: live, album: "Live at Pompeii", artist: "Pink Floyd"
        )
        #expect(chosen == ["pompeii"])
    }

    @Test func aCollaborationIsNotAnArtistDisagreement() throws {
        // MusicBrainz splits a collaboration into one credit per artist, and a
        // player usually reports the lead alone. Reduced to the first credit the
        // join would still work; reduced to nothing it would reject every
        // featured track.
        let featured = Data("""
        {"release-groups":[{"id":"g","title":"Watch the Throne","primary-type":"Album",
          "artist-credit":[{"name":"JAY-Z"},{"name":"Kanye West"}]}]}
        """.utf8)
        let chosen = try CoverArtArchiveLookup.groups(
            fromAlbumSearch: featured, album: "Watch the Throne", artist: "JAY-Z"
        )
        #expect(chosen == ["g"])
    }

    // MARK: - End to end over the injected fetch

    private func lookup(
        _ log: FetchLog = FetchLog(),
        metadata: Data = darkSideSearch,
        image: @escaping @Sendable () throws -> Data = { darkSideCover },
        pacer: RequestPacer = RequestPacer(spacing: 0)
    ) -> CoverArtArchiveLookup {
        CoverArtArchiveLookup(
            fetch: { request in
                log.note(request)
                let host = request.url?.host ?? ""
                return host.contains("musicbrainz") ? metadata : try image()
            },
            userAgent: "Crema/test ( contact )",
            pacer: pacer
        )
    }

    @Test func aMatchReturnsTheCoverBytes() async throws {
        let log = FetchLog()
        let result = await lookup(log).highResolutionArtwork(
            title: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon"
        )
        #expect(result?.count == 20_000)
        try #require(log.urls.count == 2)
        #expect(log.urls[0].contains("/ws/2/release-group"))
        // The identifier the search returned has to be the one the archive was
        // asked about — the two halves are joined by nothing else.
        #expect(log.urls[1] == "https://coverartarchive.org/release-group/dark-side/front-1200")
    }

    @Test func aTrackWhosePlayerNamedNoAlbumGoesInThroughTheRecording() async throws {
        let log = FetchLog()
        let result = await lookup(log, metadata: Self.creepRecordings).highResolutionArtwork(
            title: "Creep", artist: "Radiohead", album: nil
        )
        // Not a nicety on this path: the JXA fallback reports no album AND
        // carries no bitmap, so this is the only cover the surface will ever
        // get. Sending the album search anyway would spend the request on a
        // query that returns nothing — measured against the real endpoint.
        #expect(result?.count == 20_000)
        try #require(log.urls.count == 2)
        #expect(log.urls[0].contains("/ws/2/recording"))
        #expect(log.urls[1] == "https://coverartarchive.org/release-group/pablo-honey/front-1200")
    }

    @Test func everyRequestNamesTheAppAndAContact() async throws {
        let log = FetchLog()
        _ = await lookup(log).highResolutionArtwork(
            title: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon"
        )
        try #require(log.requests.count == 2)
        #expect(log.requests.allSatisfy {
            $0.value(forHTTPHeaderField: "User-Agent") == "Crema/test ( contact )"
        })
    }

    @Test func aRejectedMatchCostsNoSecondRequest() async {
        let log = FetchLog()
        let result = await lookup(log).highResolutionArtwork(
            title: "Ep. 412 — The Housing Crisis, Revisited", artist: "Search Engine", album: "Crisis"
        )
        #expect(result == nil)
        #expect(log.urls.count == 1, "a rejected match must not cost a request to the archive")
    }

    @Test func aThrowingFetchIsSilence() async {
        struct Offline: Error {}
        let result = await CoverArtArchiveLookup(
            fetch: { _ in throw Offline() }, userAgent: "x", pacer: RequestPacer(spacing: 0)
        ).highResolutionArtwork(title: "Breathe", artist: nil, album: "The Dark Side of the Moon")
        // No network is the common case on a laptop that just woke, and it must
        // cost the widget nothing: it already has the player's own cover.
        #expect(result == nil)
    }

    @Test func aReleaseGroupWithNoUploadedArtIsSilence() async {
        // The archive's own way of saying no. `URLSession` reports it as a
        // perfectly successful response with an error body, which is why the
        // status is checked at the edge rather than inferred from the bytes.
        let result = await lookup(image: { throw CoverArtArchiveLookup.UnexpectedStatus(code: 404) })
            .highResolutionArtwork(
                title: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon"
            )
        #expect(result == nil)
    }

    @Test func noResultsIsSilence() async {
        let result = await lookup(metadata: Data(#"{"release-groups":[]}"#.utf8))
            .highResolutionArtwork(title: "x", artist: nil, album: "Something Unreleased")
        #expect(result == nil)
    }

    @Test func aBodyThatIsNotJSONIsSilence() async {
        let result = await lookup(metadata: Data("<html>rate limited</html>".utf8))
            .highResolutionArtwork(title: "x", artist: nil, album: "The Dark Side of the Moon")
        #expect(result == nil)
    }

    @Test func aSuspiciouslySmallAnswerIsNotACover() async {
        // An error page comes back as a couple of hundred bytes. Handing that to
        // the decoder yields a blank square where a cover was.
        let result = await lookup(image: { Data(repeating: 0, count: 200) }).highResolutionArtwork(
            title: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon"
        )
        #expect(result == nil)
    }

    @Test @MainActor func aSecondLookupWaitsOutTheRateLimit() async {
        // The obligation this discharges is not the user's: exceeding the limit
        // gets the address blocked, and the address is shared with every other
        // Crema user behind it.
        let clock = TestSleepClock()
        let subject = lookup(pacer: RequestPacer(spacing: 1, clock: clock, now: { 100 }))
        _ = await subject.highResolutionArtwork(
            title: "Breathe", artist: "Pink Floyd", album: "The Dark Side of the Moon"
        )
        #expect(clock.delays.isEmpty, "the first lookup waits for nothing")

        let second = Task {
            await subject.highResolutionArtwork(
                title: "Time", artist: "Pink Floyd", album: "The Dark Side of the Moon"
            )
        }
        await clock.waitForSleep()
        #expect(clock.delays == [1])
        clock.advance()
        _ = await second.value
    }
}

private let darkSideSearch = Data("""
{"release-groups":[{"id":"dark-side","title":"The Dark Side of the Moon","primary-type":"Album",
  "artist-credit":[{"name":"Pink Floyd"}]}]}
""".utf8)

private let darkSideCover = Data(repeating: 0xAB, count: 20_000)

/// The fetch closure is `@Sendable`, so what it records cannot be a captured
/// `var`. A box under a lock says the same thing and crosses the boundary.
final class FetchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] { lock.withLock { _requests } }
    var urls: [String] { requests.map { $0.url?.absoluteString ?? "" } }

    func note(_ request: URLRequest) { lock.withLock { _requests.append(request) } }
}
