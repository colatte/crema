/// What the app is presenting on screen. Owned by the Coordinator (the single
/// source of truth); views render purely from this value.
enum PresentationState: Equatable, Sendable {
    case hidden
    case nowPlaying(NowPlaying, expanded: Bool)
    case hud(SystemHUD)
}
