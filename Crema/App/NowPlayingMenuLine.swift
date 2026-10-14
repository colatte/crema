/// What the menu bar says about the media, decided as a value so its three shapes
/// — and the media section's existence, which follows from them — are pinned
/// without a view in the loop.
///
/// Three cases because merging any two of them ships a defect: a missing artist
/// composed anyway leaves a dangling separator ("Breathe — "), and an absent
/// snapshot rendered as a name leaves a blank menu row, which reads as a broken
/// app rather than as silence.
///
/// The input is the Coordinator's title/artist MIRRORS, never `nowPlaying`: the
/// live snapshot is rewritten once per second and an observation on it would
/// rebuild the menu — and the event-tap pull-read beside it — at 1 Hz
/// (docs/DECISIONS.md: menu-reads-mirrors).
enum NowPlayingMenuLine: Equatable {
    /// No media to name: the menu shows no media section at all, rather than a
    /// blank row or a line saying so.
    case nothing
    /// A title with no artist to pair it with.
    case title(String)
    case titleAndArtist(title: String, artist: String)

    /// Both borders already normalize — a payload with no title is dropped and a
    /// blank artist becomes nil (AdapterPayloadTranslation,
    /// JXANowPlayingTranslation) — so the emptiness checks are belt and braces:
    /// they cost one condition each and they are what keeps a future third source
    /// from putting a blank row in the menu.
    init(title: String?, artist: String?) {
        guard let title, !title.isEmpty else {
            self = .nothing
            return
        }
        guard let artist, !artist.isEmpty else {
            self = .title(title)
            return
        }
        self = .titleAndArtist(title: title, artist: artist)
    }
}
