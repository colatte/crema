import Foundation
import os

/// Capability: a larger cover than the player handed over.
///
/// The adapter passes on whatever bitmap the player published — typically
/// 300–600 px, and not negotiable: `MRMediaRemoteGetNowPlayingInfo` takes no
/// options dictionary, so there is no size to ask for and the dimensions
/// received are not even reported. Fine behind a 50 pt thumbnail. Visibly soft
/// as a 300 pt cover filling a lock screen.
///
/// A capability rather than a function because the honest answer is usually
/// "no": no match, no network, feature off. Every one of those is silence, and
/// the surface must be complete without it.
protocol ArtworkLookup: Sendable {
    /// Nil for every failure, and they are all the same failure to the caller:
    /// the widget falls back to the bytes it already has.
    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]?
}

/// The iTunes Search API, which is public and takes no token, no account and no
/// developer program — verified against the endpoint before this was written.
///
/// **On the way out, and the reason is the terms rather than the technique.**
/// The Search API grants the use of album art only on a page promoting that
/// content, next to a "Download on iTunes" badge, and never "for independent
/// entertainment value apart from its promotional purpose" — which is exactly
/// what a cover filling a lock screen is. The replacement is the Cover Art
/// Archive (MusicBrainz), which exists for this use and asks for no badge;
/// `ArtworkLookup` is a protocol precisely so the swap costs one conformer
/// (docs/DECISIONS.md: the-cover-comes-from-the-archive-not-the-store).
///
/// ## Why this endpoint and not the Apple Music API
///
/// The catalog API needs a MusicKit developer token signed with a key from the
/// Apple Developer program, which this app does not have (the same absence that
/// keeps it self-signed rather than notarized) and could not embed in an
/// open-source binary anyway. The Search API needs none of that.
///
/// ## Why 1200
///
/// Rewriting the size in the returned artwork URL is the documented trick and
/// the sizes are fixed — measured against a real track: 600 → 98 KB,
/// **1200 → 391 KB**, 3000 → 2.7 MB, and above 3000 Apple caps rather than
/// erroring. 1200 covers a 300 pt hero at 2× with room to spare, at a seventh of
/// 3000's weight, on a surface that is decoration rather than the point.
///
/// ## Why it is off by default, and why it leaves nothing behind
///
/// It is a network request carrying what you are listening to. Not an account
/// and not analytics — the two things the app promises it does not do — but
/// traffic tied to listening all the same, and that is the user's call to make
/// rather than ours to make quietly.
///
/// Which is exactly why it does not use `URLSession.shared`. That session writes
/// through the shared on-disk `URLCache` under `~/Library/Caches`, so both
/// halves of every lookup — the search URL, which spells the title, artist and
/// album in its query string, and the ~391 KB cover — would be written to disk
/// and **survive the user switching the feature back off**. A preference that
/// stops the traffic but leaves the history is not the promise the Settings
/// footer makes. `.ephemeral` keeps cache, cookies and credentials in memory
/// only, and the session dies with the process.
///
/// Nothing is lost by it: the resolver already caches the one cover it is
/// showing, and a lookup happens once per track identity, so there was no
/// second request for a disk cache to serve.
final class ITunesArtworkLookup: ArtworkLookup {
    /// Injectable so the tests never touch the network: they hand back canned
    /// JSON and canned image bytes and assert on what was asked for.
    typealias Fetch = @Sendable (URL) async throws -> Data

    private let fetch: Fetch
    private let logger = Logger.crema("NowPlaying")

    /// The size to rewrite `100x100bb.jpg` into. Not arbitrary — see the note
    /// above; the endpoint only serves a fixed set and 1200 is the one that
    /// fits.
    static let targetPixelSize = 1200

    /// A cover that came back implausibly small is a redirect or an error page,
    /// not artwork; below this the answer is treated as no answer.
    private static let minimumPlausibleBytes = 4096

    init(fetch: @escaping Fetch = ITunesArtworkLookup.urlSessionFetch) {
        self.fetch = fetch
    }

    /// One ephemeral session for the process, built once rather than per call —
    /// a session per request leaks connections and re-pays TLS every time.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Belt to the ephemeral braces: `.ephemeral` already keeps the cache in
        // memory, and this says the request must not be answered from one
        // either — a cover served from a stale cache is a cover for the wrong
        // track after the endpoint changed its art.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        // Nothing waits on this, so it must never wait for a network to come
        // back: the surface is complete with the player's own cover, and a
        // request parked until Wi-Fi returns would fire an upgrade for a song
        // that stopped playing an hour ago.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url)
        // Short, because nothing waits on this: the surface is already drawn
        // with the player's own cover by the time an answer could arrive.
        request.timeoutInterval = 8
        let (data, _) = try await session.data(for: request)
        return data
    }

    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]? {
        guard let query = Self.searchURL(title: title, artist: artist, album: album) else { return nil }
        do {
            let response = try await JSONDecoder().decode(ITunesSearchResponse.self, from: fetch(query))
            // The endpoint always answers with SOMETHING, and it is pinned to
            // `entity=song`, so every answer is a song whether or not a song was
            // playing. Taking the top hit unchecked meant a podcast episode, an
            // audiobook or a live stream — all of which carry correct artwork of
            // their own — could have it replaced by an unrelated album cover.
            // Wrong art is worse than none: the fallback was already right.
            guard let match = response.results.first(where: {
                ArtworkMatch.plausible(
                    requestedTitle: title, requestedArtist: artist,
                    resultTitle: $0.trackName, resultArtist: $0.artistName
                )
            }) else {
                logger.info("artwork lookup found no plausible match")
                return nil
            }
            guard let small = match.artworkUrl100,
                  let large = Self.resized(small, to: Self.targetPixelSize) else { return nil }
            let bytes = try await fetch(large)
            guard bytes.count >= Self.minimumPlausibleBytes else {
                logger.info("artwork lookup returned \(bytes.count) bytes — too small to be a cover")
                return nil
            }
            return Array(bytes)
        } catch {
            // Every failure is the same failure here: no network, a decode that
            // did not fit, a 404. The widget already has a cover to show.
            logger.info("artwork lookup found nothing for \(title, privacy: .private)")
            return nil
        }
    }

    // MARK: - Pure parts, so a test owns them without a network

    /// Title, artist and album together. The album is why this was worth adding
    /// a field for: two terms match the wrong single off a compilation often
    /// enough to matter, and the adapter was already emitting the third.
    static func searchURL(title: String, artist: String?, album: String?) -> URL? {
        let terms = [title, artist, album].compactMap(\.self).filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: terms.joined(separator: " ")),
            URLQueryItem(name: "entity", value: "song"),
            // More than one, now that the answers are checked: the top hit is
            // often a remaster or a live version of the right song, and a
            // slightly-off first result should not cost the whole lookup. Still
            // one request.
            URLQueryItem(name: "limit", value: "5"),
        ]
        return components?.url
    }

    /// The endpoint returns a 100 px URL and the size is a path component, so a
    /// larger cover is a substitution rather than another request for metadata.
    /// Returns nil when the URL is not the shape this rewrite understands —
    /// guessing at an unfamiliar path would fetch a 404 at best.
    static func resized(_ artworkURL: String, to pixels: Int) -> URL? {
        let marker = "100x100bb"
        guard artworkURL.contains(marker) else { return nil }
        return URL(string: artworkURL.replacingOccurrences(of: marker, with: "\(pixels)x\(pixels)bb"))
    }
}

/// The two fields of the search response this cares about. Everything else the
/// endpoint returns (track ids, prices, preview URLs, genre) is deliberately not
/// modelled: a `Decodable` that names a field is a field this app now depends on
/// the shape of.
private struct ITunesSearchResponse: Decodable {
    let results: [Match]

    struct Match: Decodable {
        /// Optional because a match without artwork is a legitimate answer, and
        /// a decode that threw on it would turn "no cover" into "no result".
        let artworkUrl100: String?
        /// What the endpoint thinks it found. Read only to reject it
        /// (`ArtworkMatch`) — never rendered, so nothing the endpoint says
        /// reaches the screen as text.
        let trackName: String?
        let artistName: String?
    }
}

/// Whether a search result is plausibly the track that is playing.
///
/// Pure and separate because it is the whole judgement, and because the
/// alternative — trusting the endpoint's top hit — has a specific victim:
/// `entity=song` guarantees every answer is a song, so a podcast episode, an
/// audiobook chapter or a live stream would have its own correct artwork
/// replaced by an unrelated album cover. The bar is deliberately generous, not
/// exact: the goal is to reject the unrelated, not to demand the identical.
enum ArtworkMatch {
    /// Case, accents, punctuation and the parenthetical tail all removed —
    /// "Algernon (Remastered 2023)" and "algernon" have to meet. The tail is
    /// where remasters, live versions and feature credits live, and they are
    /// the same recording's cover often enough to keep.
    static func normalized(_ value: String) -> String {
        let withoutTail = value.replacingOccurrences(
            of: #"[\(\[].*?[\)\]]"#, with: " ", options: .regularExpression
        )
        let folded = withoutTail.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let letters = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// Equal after normalizing, or one a PREFIX of the other at a word boundary.
    ///
    /// Prefix rather than containment anywhere, and the difference is not
    /// theoretical — a mutation found it. Plain containment accepted "Crisis"
    /// for a podcast episode called "Ep. 412 — The Housing Crisis, Revisited",
    /// because the long title happens to contain the short one. Only the artist
    /// check was refusing that result, so a podcast reporting no artist would
    /// have taken a stranger's album cover.
    ///
    /// Prefix keeps every case containment was there for: what the two sides
    /// disagree about is a TAIL — " feat. X", " - Remastered", " - Single" — and
    /// a tail is exactly what a prefix tolerates. Empty on either side is no
    /// evidence, so it can never be the thing that accepts a result.
    static func agrees(_ requested: String, _ found: String?) -> Bool {
        let want = normalized(requested)
        guard let found, !want.isEmpty else { return false }
        let got = normalized(found)
        guard !got.isEmpty else { return false }
        if want == got { return true }
        let (shorter, longer) = want.count < got.count ? (want, got) : (got, want)
        // The boundary matters: without it "Love" would be a prefix of
        // "Lovesong", which is a different record with different art.
        return longer.hasPrefix(shorter + " ")
    }

    /// The title must agree. The artist only has to agree when BOTH sides named
    /// one — the JXA fallback often reports no artist, and refusing every lookup
    /// for those tracks would turn a missing field into a missing feature.
    static func plausible(
        requestedTitle: String,
        requestedArtist: String?,
        resultTitle: String?,
        resultArtist: String?
    ) -> Bool {
        guard agrees(requestedTitle, resultTitle) else { return false }
        guard let requestedArtist, !requestedArtist.isEmpty, resultArtist?.isEmpty == false else {
            return true
        }
        return agrees(requestedArtist, resultArtist)
    }
}
