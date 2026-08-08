import Foundation
import os

/// The Cover Art Archive, addressed through MusicBrainz — a cover source that
/// exists to be used this way.
///
/// ## Why not Apple's search endpoint, which this replaced
///
/// Not technique: the iTunes Search API worked, took no token and returned a
/// 1200 px cover. Its terms are what disqualify it — album art is licensed there
/// for pages promoting that content, beside a "Download on iTunes" badge, and
/// never "for independent entertainment value apart from its promotional
/// purpose". A cover filling a lock screen is precisely the excluded use. The
/// archive asks for no badge and no account (docs/DECISIONS.md:
/// the-cover-comes-from-the-archive-not-the-store).
///
/// ## The two halves, and why only one is paced
///
/// MusicBrainz answers "which release group is this", the archive serves its
/// cover. MusicBrainz publishes a hard **one request per second per IP** and
/// requires a User-Agent naming the application and a way to reach its
/// maintainer; a request without one is refused. The archive publishes neither
/// requirement — "there are currently no rate limiting rules in place" — so the
/// image half goes straight out, carrying the same header only out of courtesy.
///
/// ## Why the album is the search, and what happens without one
///
/// A release group is an album, so its cover is the same for every track on it —
/// searching the album is both more accurate and cacheable per record rather than
/// per track. Without an album the only way in is the recording, and that path
/// was measured before it was written: "Creep" by Radiohead returns eight live
/// bootlegs ahead of *Pablo Honey*, every one of them a real release with real,
/// wrong art. `secondary-types` separates them cleanly — the studio album is the
/// only answer carrying none — so the guessed path demands an empty one. The
/// album path must not: someone playing a live record should get the live
/// record's cover.
///
/// ## Why 1200
///
/// The archive serves 250, 500 and 1200 as fixed sizes. Measured on a real
/// release group: 500 → 18 KB, **1200 → 77 KB**. 1200 covers a 300 pt hero at 2×
/// with room to spare, on a surface that is decoration rather than the point.
///
/// ## Why it is off by default, and why it leaves nothing behind
///
/// It is a network request carrying what you are listening to. Not an account
/// and not analytics — the two things the app promises it does not do — but
/// traffic tied to listening all the same, and that is the user's call to make
/// rather than ours to make quietly.
///
/// Which is exactly why it does not use `URLSession.shared`. That session writes
/// through the shared on-disk `URLCache` under `~/Library/Caches`, so both halves
/// of every lookup — the search URL, which spells the album and artist in its
/// query string, and the cover itself — would be written to disk and **survive
/// the user switching the feature back off**. A preference that stops the traffic
/// but leaves the history is not the promise the Settings footer makes.
/// `.ephemeral` keeps cache, cookies and credentials in memory only, and the
/// session dies with the process.
final class CoverArtArchiveLookup: ArtworkLookup {
    /// Injectable so the tests never touch the network. A `URLRequest` rather
    /// than a `URL` because the header is part of the contract with MusicBrainz,
    /// and a test that could not see it could not pin it.
    typealias Fetch = @Sendable (URLRequest) async throws -> Data

    private let fetch: Fetch
    private let userAgent: String
    private let pacer: RequestPacer
    private let logger = Logger.crema("NowPlaying")

    /// One of the three sizes the archive serves — see the note above.
    static let targetPixelSize = 1200

    /// MusicBrainz's published limit, one request per second per source IP.
    static let musicBrainzSpacing: Double = 1

    /// A cover that came back implausibly small is an error page, not artwork;
    /// below this the answer is treated as no answer.
    private static let minimumPlausibleBytes = 4096

    /// Enough results that a top hit which fails the plausibility gate does not
    /// cost the whole lookup, and still one request.
    private static let searchLimit = 5

    init(
        fetch: @escaping Fetch = CoverArtArchiveLookup.urlSessionFetch,
        userAgent: String = CoverArtArchiveLookup.defaultUserAgent(),
        pacer: RequestPacer = RequestPacer(spacing: CoverArtArchiveLookup.musicBrainzSpacing)
    ) {
        self.fetch = fetch
        self.userAgent = userAgent
        self.pacer = pacer
    }

    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]? {
        guard let group = await releaseGroup(title: title, artist: artist, album: album),
              let cover = Self.coverURL(releaseGroup: group) else { return nil }
        do {
            let bytes = try await fetch(request(cover))
            guard bytes.count >= Self.minimumPlausibleBytes else {
                logger.info("cover lookup returned \(bytes.count) bytes — too small to be artwork")
                return nil
            }
            return Array(bytes)
        } catch {
            // Every failure is the same failure here: no network, a 404 for a
            // release group nobody has uploaded art for, a body that did not
            // decode. The widget already has a cover to show, or has honestly
            // shown none since the track started.
            logger.info("cover lookup found no image for \(album ?? title, privacy: .private)")
            return nil
        }
    }

    /// The metadata half: one paced, User-Agent-bearing request to MusicBrainz,
    /// and the judgement about whether its answer is the record that is playing.
    private func releaseGroup(title: String, artist: String?, album: String?) async -> String? {
        // A blank album is the same as none: the player published the field and
        // left it empty, and a blank Lucene phrase matches nothing.
        let album = album.flatMap { $0.isEmpty ? nil : $0 }
        let search = album.map { Self.releaseGroupSearchURL(album: $0, artist: artist) }
            ?? Self.recordingSearchURL(title: title, artist: artist)
        guard let search else { return nil }

        await pacer.waitForTurn()
        // The pacer does not observe cancellation, so a track that changed while
        // this sat in the queue is caught here rather than costing a request.
        guard !Task.isCancelled else { return nil }

        do {
            let data = try await fetch(request(search))
            let candidates = try album.map {
                try Self.groups(fromAlbumSearch: data, album: $0, artist: artist)
            } ?? Self.groups(fromRecordingSearch: data, title: title, artist: artist)
            guard let first = candidates.first else {
                logger.info("cover lookup found no plausible release group")
                return nil
            }
            return first
        } catch {
            logger.info("cover lookup found nothing for \(album ?? title, privacy: .private)")
            return nil
        }
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        // Mandatory for MusicBrainz, which refuses a request that does not name
        // the application and a way to reach whoever maintains it.
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        // Short, because nothing waits on this: the surface is already drawn by
        // the time an answer could arrive.
        request.timeoutInterval = 8
        return request
    }

    // MARK: - The edge

    /// One ephemeral session for the process, built once rather than per call —
    /// a session per request leaks connections and re-pays TLS every time.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // Belt to the ephemeral braces: `.ephemeral` already keeps the cache in
        // memory, and this says the request must not be answered from one
        // either — a cover served from a stale cache is a cover for the wrong
        // record after the archive replaced its art.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 8
        // Nothing waits on this, so it must never wait for a network to come
        // back: the surface is complete with the player's own cover, and a
        // request parked until Wi-Fi returns would fire an upgrade for a song
        // that stopped playing an hour ago.
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    /// A status this endpoint pair uses to say "no", which `URLSession` reports
    /// as a perfectly successful response with a body. The archive answers 404
    /// for a release group with no art and 400 for a malformed identifier;
    /// letting either through would hand an error page to the decoder.
    struct UnexpectedStatus: Error {
        let code: Int
    }

    static let urlSessionFetch: Fetch = { request in
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UnexpectedStatus(code: http.statusCode)
        }
        return data
    }

    // MARK: - Pure parts, so a test owns them without a network

    /// Names the app and a way to reach its maintainers, which is what
    /// MusicBrainz asks for in exchange for an unauthenticated endpoint.
    static func defaultUserAgent(version: String = shortVersion) -> String {
        "Crema/\(version) ( https://github.com/colatte/crema )"
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// A quoted Lucene phrase. The quoting is not decoration: inside quotes every
    /// special character is literal except `"` and `\`, and a title containing one
    /// is ordinary — Bowie's `"Heroes"` is spelled with them. Unescaped, it ends
    /// the phrase early and the rest of the title becomes query syntax.
    static func phrase(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func releaseGroupSearchURL(album: String, artist: String?) -> URL? {
        guard !album.isEmpty else { return nil }
        return searchURL(entity: "release-group", field: "releasegroup", value: album, artist: artist)
    }

    static func recordingSearchURL(title: String, artist: String?) -> URL? {
        guard !title.isEmpty else { return nil }
        return searchURL(entity: "recording", field: "recording", value: title, artist: artist)
    }

    private static func searchURL(entity: String, field: String, value: String, artist: String?) -> URL? {
        var query = "\(field):\(phrase(value))"
        if let artist, !artist.isEmpty {
            query += " AND artist:\(phrase(artist))"
        }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/\(entity)/")
        components?.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "\(searchLimit)"),
        ]
        return components?.url
    }

    static func coverURL(releaseGroup identifier: String) -> URL? {
        guard !identifier.isEmpty else { return nil }
        var components = URLComponents(string: "https://coverartarchive.org/release-group/")
        components?.path += "\(identifier)/front-\(targetPixelSize)"
        return components?.url
    }

    /// Release groups from an album search, in the order MusicBrainz ranked them,
    /// keeping only those that plausibly name the record that is playing.
    static func groups(fromAlbumSearch data: Data, album: String, artist: String?) throws -> [String] {
        try JSONDecoder().decode(ReleaseGroupSearch.self, from: data).releaseGroups
            .filter {
                // The album is the title being matched here — the release group
                // IS the record, and its own name is what the search asked for.
                ArtworkMatch.plausible(
                    requestedTitle: album, requestedArtist: artist,
                    resultTitle: $0.title, resultArtist: $0.credited
                )
            }
            .map(\.id)
    }

    /// Release groups reached through a recording, for a track whose player never
    /// said which record it came from. Restricted to groups with no secondary
    /// type, which is what separates the studio album from the live bootlegs that
    /// otherwise rank above it — measured, and the reason this path is written
    /// differently from the one above.
    static func groups(fromRecordingSearch data: Data, title: String, artist: String?) throws -> [String] {
        try JSONDecoder().decode(RecordingSearch.self, from: data).recordings
            .filter {
                ArtworkMatch.plausible(
                    requestedTitle: title, requestedArtist: artist,
                    resultTitle: $0.title, resultArtist: $0.credited
                )
            }
            .flatMap { $0.releases ?? [] }
            .compactMap(\.releaseGroup)
            .filter { $0.secondaryTypes?.isEmpty ?? true }
            .map(\.id)
    }
}

// MARK: - The shapes of the two answers

/// Only the fields the judgement needs. Everything else MusicBrainz returns
/// (scores, disambiguations, release dates, label info) is deliberately not
/// modelled: a `Decodable` that names a field is a field this app now depends on
/// the shape of.
private struct ReleaseGroupSearch: Decodable {
    let releaseGroups: [MusicBrainzGroup]

    enum CodingKeys: String, CodingKey {
        case releaseGroups = "release-groups"
    }
}

private struct RecordingSearch: Decodable {
    let recordings: [MusicBrainzRecording]
}

private struct MusicBrainzRecording: Decodable {
    /// What MusicBrainz thinks it found. Read only to reject it
    /// (`ArtworkMatch`) — never rendered, so nothing the endpoint says reaches
    /// the screen as text.
    let title: String?
    let artistCredit: [MusicBrainzCredit]?
    let releases: [MusicBrainzRelease]?

    var credited: String? { MusicBrainzCredit.joined(artistCredit) }

    enum CodingKeys: String, CodingKey {
        case title, releases
        case artistCredit = "artist-credit"
    }
}

private struct MusicBrainzRelease: Decodable {
    let releaseGroup: MusicBrainzGroup?

    enum CodingKeys: String, CodingKey {
        case releaseGroup = "release-group"
    }
}

private struct MusicBrainzGroup: Decodable {
    let id: String
    let title: String?
    /// "Live", "Compilation", "Demo", "Soundtrack" and the rest. Absent on a
    /// plain studio record, which is the whole discriminator on the guessed path.
    let secondaryTypes: [String]?
    let artistCredit: [MusicBrainzCredit]?

    var credited: String? { MusicBrainzCredit.joined(artistCredit) }

    enum CodingKeys: String, CodingKey {
        case id, title
        case secondaryTypes = "secondary-types"
        case artistCredit = "artist-credit"
    }
}

private struct MusicBrainzCredit: Decodable {
    let name: String?

    /// A collaboration arrives as several credits. Joined rather than reduced to
    /// the first, because `ArtworkMatch` tolerates a tail: a player reporting
    /// only the lead artist still agrees with "Lead Featured".
    static func joined(_ credits: [Self]?) -> String? {
        guard let credits else { return nil }
        let names = credits.compactMap(\.name).filter { !$0.isEmpty }
        return names.isEmpty ? nil : names.joined(separator: " ")
    }
}
