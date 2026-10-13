import Foundation

/// Translates the JXA probe's JSON output into NowPlaying. The probe emits a
/// flat object ({title, artist, duration, position, playing}) or {} when
/// nothing is playing; artwork is never present (a JXA fallback limitation).
enum JXANowPlayingTranslation {
    static func nowPlaying(fromJSON json: String) -> NowPlaying? {
        guard let data = json.data(using: .utf8),
              let track = try? JSONDecoder().decode(Track.self, from: data),
              let title = track.title, !title.isEmpty else {
            return nil
        }
        // sourceBundleID stays nil: the probe only ever talks to Spotify and
        // Apple Music — never a browser — and nil is a safe default for the
        // browser filter (nil = not a browser).
        // The duration takes the adapter's rule (positive, finite, under a day) and
        // the position the domain's bound: both are what the player chose.
        let duration = track.duration.flatMap { $0 > 0 && $0 < NowPlaying.maximumPosition ? $0 : nil }
        return NowPlaying(
            title: title,
            artist: track.artist.flatMap { $0.isEmpty ? nil : $0 },
            artworkData: nil,
            isPlaying: track.playing ?? false,
            position: NowPlaying.bounded(position: track.position ?? 0, duration: duration),
            duration: duration
        )
    }

    private struct Track: Decodable {
        let title: String?
        let artist: String?
        let duration: Double?
        let position: Double?
        let playing: Bool?
    }
}
