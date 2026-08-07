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
/// ## Why it is off by default
///
/// It is a network request carrying what you are listening to. Not an account
/// and not analytics — the two things the app promises it does not do — but
/// traffic tied to listening all the same, and that is the user's call to make
/// rather than ours to make quietly.
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

    static let urlSessionFetch: Fetch = { url in
        var request = URLRequest(url: url)
        // Short, because nothing waits on this: the surface is already drawn
        // with the player's own cover by the time an answer could arrive.
        request.timeoutInterval = 8
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]? {
        guard let query = Self.searchURL(title: title, artist: artist, album: album) else { return nil }
        do {
            let response = try await JSONDecoder().decode(ITunesSearchResponse.self, from: fetch(query))
            guard let small = response.results.first?.artworkUrl100,
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
            URLQueryItem(name: "limit", value: "1"),
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
    }
}
