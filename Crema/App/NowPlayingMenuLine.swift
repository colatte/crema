/// What the menu bar says about the media, decided as a value so its three shapes
/// — and the transport gate that follows from them — are pinned without a view in
/// the loop.
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
    /// No media to name. Said in words, because a blank row says nothing.
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

    /// Whether the line names real media — the menu transport's own gate, and
    /// deliberately derived from the SAME value the row is drawn from. A separate
    /// `title != nil` test is how the two drift: the emptiness guard above turns a
    /// blank title into "Nothing playing" while that test still reports media,
    /// which is an enabled Pause over a row saying nothing is playing.
    var namesMedia: Bool {
        self != .nothing
    }
}
