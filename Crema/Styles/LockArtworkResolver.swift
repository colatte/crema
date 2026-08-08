import Observation

/// Which cover the lock surface should draw: the player's own, or a larger one
/// fetched for it.
///
/// It exists because the choice has to be made somewhere that is neither the
/// view (which must not know about networks) nor the lookup (which must not
/// know about preferences or about what is on screen). The view asks for one
/// track's cover and gets bytes; everything else happens here.
///
/// The fallback is the invariant: `artwork(for:)` always returns something the
/// moment it is called, and an answer that arrives later only ever replaces a
/// cover with a better one. Nothing waits, nothing blanks.
@Observable
@MainActor
final class LockArtworkResolver {
    private let lookup: any ArtworkLookup

    /// Off by default and flipped by Settings, like the surface itself. Held
    /// rather than read from `Preferences` so this type never learns what a
    /// preference is; readable because it is the one thing about this type an
    /// outside caller can meaningfully ask, and because it is how the composition
    /// root's seeding of it is pinned at all.
    private(set) var isEnabled: Bool

    /// The high-resolution answer for `resolvedIdentity`, and only for it. Both
    /// are cleared together, because bytes without the identity they belong to
    /// are how one track's cover lands on the next track's surface.
    private var upgraded: [UInt8]?
    private var resolvedIdentity: String?

    init(lookup: any ArtworkLookup = CoverArtArchiveLookup(), enabled: Bool) {
        self.lookup = lookup
        isEnabled = enabled
    }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        // Turning it off must take effect on the surface that is up, not on the
        // next track: the user switched it off for a reason.
        if !on {
            upgraded = nil
            resolvedIdentity = nil
        }
    }

    /// Title, artist and album — every field the lookup reads, so a track that
    /// changes only in position (the 1 Hz tick) is the same identity and never
    /// re-asks. All three, even though a given lookup searches on some of them:
    /// which ones it uses is the lookup's business to change, and an identity
    /// narrower than its inputs would serve a stale answer to a new question.
    static func identity(of track: NowPlaying) -> String {
        [track.title, track.artist ?? "", track.album ?? ""].joined(separator: "\u{1F}")
    }

    /// What to draw right now. Never nil-when-the-player-had-something: the
    /// upgrade is an improvement on the fallback, never a replacement for
    /// having one.
    func artwork(for track: NowPlaying) -> [UInt8]? {
        guard resolvedIdentity == Self.identity(of: track) else { return track.artworkData }
        return upgraded ?? track.artworkData
    }

    /// Called from the view's `.task(id:)`, so cancellation comes for free when
    /// the track changes mid-flight.
    func resolve(_ track: NowPlaying) async {
        let wanted = Self.identity(of: track)
        guard isEnabled, resolvedIdentity != wanted else { return }

        let found = await lookup.highResolutionArtwork(
            title: track.title, artist: track.artist, album: track.album
        )
        // The track may have moved on while the request was in flight, and a
        // cancelled task must not publish: the successor's cover is already on
        // screen and this one would replace it with the wrong album.
        guard !Task.isCancelled, isEnabled else { return }
        upgraded = found
        resolvedIdentity = wanted
    }
}
