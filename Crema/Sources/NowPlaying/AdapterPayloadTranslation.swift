import Foundation

/// Translates one adapter JSON line into a domain NowPlaying, at the border —
/// no adapter/JSON type escapes above this. Lines that are not a `data` event,
/// or carry an empty payload / no title, mean "nothing playing" and map to nil.
///
/// Position: the payload's elapsed time is an anchor — the position at the
/// payload's timestamp, not at delivery. Players register the pair on state
/// changes and don't re-report during normal playback, so any re-emission
/// (play/pause always, artwork or metadata sometimes) carries the last anchor;
/// using it raw rewinds the scrubber by however long the anchor had aged — the
/// visible backward jump on play/pause. The translation compensates:
/// position = elapsed + (now − timestamp) × rate while playing (a paused
/// anchor doesn't age), with `now` injected so the math stays pure. Stream
/// mode runs with --micros because the plain `timestamp` is ISO truncated to
/// whole seconds — up to 1 s of error, the same order as the drift being
/// compensated; the second-based keys remain as fallback.
///
/// The source runs the adapter with `--no-diff`, so every line is a full
/// snapshot and this translation stays stateless (no diff-merge to maintain).
enum AdapterPayloadTranslation {
    /// The snapshot plus the one mechanism value the source needs but the views
    /// never do: the playback rate. It stays out of the domain deliberately —
    /// `NowPlaying` describes what is shown, and a rate field would ride along
    /// in `layoutContent`, making a speed change read as a content change (a
    /// podcast at 1.5× would pop the surface like a new track).
    struct Snapshot {
        let nowPlaying: NowPlaying
        /// 1 when the payload omits it, matching the position math's own default.
        let rate: Double
    }

    static func snapshot(fromLine line: String, at now: Date) -> Snapshot? {
        guard let data = line.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.type == "data",
              let payload = envelope.payload,
              let title = payload.title, !title.isEmpty else {
            return nil
        }
        return Snapshot(
            nowPlaying: nowPlaying(from: payload, title: title, at: now),
            rate: payload.playbackRate ?? 1
        )
    }

    static func nowPlaying(fromLine line: String, at now: Date) -> NowPlaying? {
        snapshot(fromLine: line, at: now)?.nowPlaying
    }

    private static func nowPlaying(from payload: Payload, title: String, at now: Date) -> NowPlaying {
        NowPlaying(
            title: title,
            artist: payload.artist.flatMap { $0.isEmpty ? nil : $0 },
            artworkData: payload.artworkData.flatMap { Data(base64Encoded: $0).map(Array.init) },
            isPlaying: payload.playing ?? false,
            position: position(of: payload, at: now),
            duration: payload.durationSeconds,
            // The parent is the real app when media plays through a helper
            // process (browsers report a WebKit client with the browser as
            // parent) — prefer it so the browser filter sees the browser.
            sourceBundleID: payload.parentApplicationBundleIdentifier ?? payload.bundleIdentifier,
            // Sending a skip to prohibiting media (radio, live) still exits 0 —
            // the command is delivered and ignored — so this metadata is the
            // only signal that the skip controls would dead-click.
            supportsSkip: !(payload.prohibitsSkip ?? false)
        )
    }

    private static func position(of payload: Payload, at now: Date) -> Double {
        // A missing elapsed key means the player reported no position at all —
        // aging a fabricated zero would invent minutes of playback, and live
        // content has no usable duration to clamp it back (its sentinel is
        // dropped by `durationSeconds`).
        guard let anchor = payload.elapsedSeconds else { return 0 }
        guard payload.playing ?? false, let anchorDate = payload.anchorDate else {
            return anchor
        }
        // A future-dated anchor (clock skew) must not rewind: it contributes 0.
        let age = max(0, now.timeIntervalSince(anchorDate))
        let advanced = anchor + age * (payload.playbackRate ?? 1)
        if let duration = payload.durationSeconds {
            return min(advanced, duration)
        }
        return advanced
    }

    private struct Envelope: Decodable {
        let type: String
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let title: String?
        let artist: String?
        let playing: Bool?
        let elapsedTime: Double?
        let elapsedTimeMicros: Double?
        let duration: Double?
        let durationMicros: Double?
        let timestamp: String?
        let timestampEpochMicros: Double?
        let playbackRate: Double?
        let artworkData: String?
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let prohibitsSkip: Bool?

        var elapsedSeconds: Double? {
            elapsedTimeMicros.map { $0 / 1_000_000 } ?? elapsedTime
        }

        /// Live content does report a duration: MediaRemote's "no end" sentinel
        /// is LLONG_MAX, measured on the wire as `durationMicros:
        /// 9.2233720368547758e+18` — 292 thousand years, which sails past a
        /// plain `> 0` test. Sanitising here, at the border, is what makes the
        /// domain's promise true (`NowPlaying.duration` is nil when the player
        /// reports none) and keeps the sentinel out of the seek math, where
        /// `Int(seconds × 1e6)` on it lands exactly on 2^63 and traps.
        var durationSeconds: Double? {
            guard let raw = durationMicros.map({ $0 / 1_000_000 }) ?? duration,
                  raw.isFinite, raw > 0, raw < 24 * 60 * 60 else { return nil }
            return raw
        }

        var anchorDate: Date? {
            if let timestampEpochMicros {
                return Date(timeIntervalSince1970: timestampEpochMicros / 1_000_000)
            }
            return timestamp.flatMap { ISO8601DateFormatter().date(from: $0) }
        }
    }
}
