/// What the app presents, as two layers: the now-playing appearance and the
/// system HUD. Held apart because a surface may draw either one alone — the Card
/// puts a HUD placed off its own spot on a surface of its own
/// (docs/DECISIONS.md: card-hud-placement) — while a surface drawing both shows
/// the HUD over the appearance, which comes back when the HUD leaves.
struct PresentationLayers: Equatable, Sendable {
    /// A visible now-playing appearance: the layout snapshot it shows and
    /// whether it is the expanded player.
    struct Appearance: Equatable, Sendable {
        var track: NowPlaying
        var expanded: Bool
    }

    /// Which layers a surface draws, named by whoever reports an event from it.
    enum Surface: Equatable, Hashable, Sendable {
        /// Both layers on one surface, the HUD over the appearance.
        case both
        case nowPlaying
        case hud

        var drawsNowPlaying: Bool { self != .hud }
        var drawsHUD: Bool { self != .nowPlaying }
    }

    var nowPlaying: Appearance?
    var hud: SystemHUD?

    /// What `surface` shows of the two layers.
    func state(on surface: Surface) -> PresentationState {
        if surface.drawsHUD, let hud { return .hud(hud) }
        if surface.drawsNowPlaying, let nowPlaying {
            return .nowPlaying(nowPlaying.track, expanded: nowPlaying.expanded)
        }
        return .hidden
    }
}
