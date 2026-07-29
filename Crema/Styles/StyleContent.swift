/// Which surface a skin should render for a given state. Shared pure mapping
/// so every style derives its content from `PresentationState` the same way.
/// `showsNowPlaying` and `showsHUD` are the per-display policy: with either off
/// the matching content maps to empty — content-level suppression, because the
/// fixed window can no longer hide a display by ordering out. They are separate
/// because their reasons are: one is the user's preference, the other is which
/// display a reading belongs to.
enum StyleContent: Equatable {
    case empty
    case nowPlayingCompact(NowPlaying)
    case nowPlayingExpanded(NowPlaying)
    case hud(SystemHUD)

    init(state: PresentationState, showsNowPlaying: Bool = true, showsHUD: Bool = true) {
        switch state {
        case .hidden:
            self = .empty
        case let .nowPlaying(track, expanded):
            self = showsNowPlaying
                ? (expanded ? .nowPlayingExpanded(track) : .nowPlayingCompact(track))
                : .empty
        case .hud(let hud):
            self = showsHUD ? .hud(hud) : .empty
        }
    }

    /// Track identity driving the adaptive-width animation on the hugging
    /// skins. Derives from the state payload — ticks never rewrite it, so
    /// playback cannot make the width breathe. A plain equality key with an
    /// unambiguous delimiter (title "A — B" vs artist "B" stay distinct), not
    /// user-visible text.
    var adaptiveWidthKey: String? {
        switch self {
        case .nowPlayingCompact(let track), .nowPlayingExpanded(let track):
            "\(track.title)\u{1F}\(track.artist ?? "")"
        case .empty, .hud:
            nil
        }
    }
}
