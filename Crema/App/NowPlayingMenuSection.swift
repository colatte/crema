import SwiftUI

/// The menu's media group: what is playing, then the transport that acts on it.
///
/// A separate View for a load-bearing reason, not for tidiness: SwiftUI tracks
/// observation per BODY, so a track change repaints this one and leaves the scene
/// body — and CremaMenu — alone; a rebuild of that block costs a
/// CGGetEventTapList, which resets every tap's latency stats on the machine. For
/// the same reason this reads the Coordinator's title/artist MIRRORS and never
/// `nowPlaying`, which is rewritten once per second: an observation on the live
/// snapshot would rebuild the menu (and re-run that pull-read) at 1 Hz
/// (docs/DECISIONS.md: menu-reads-mirrors). Keep both properties out of
/// `CremaApp.body` — moving either read up there gives the expensive body a
/// dependency on the media state.
///
/// Availability is rendered here, never decided here: `commandsAvailable` and
/// `skipControlsEnabled` are the Coordinator's verdicts, the same two the
/// surface's transport binds to (SurfaceStyleBody) — one decision, two renderers.
/// Only "is there media at all" is added, because the surface exists only when
/// media does and this menu exists always.
///
/// The two questions are answered differently on purpose. A command the player
/// REFUSED greys its item in place, so the block keeps its shape as availability
/// moves (the rule TransportControls follows for the same reason). Media that does
/// not exist takes the three items away instead: there is no object to act on, and
/// three permanently dead verbs under "Nothing playing" are the one part of this
/// menu no user can ever use — the surface never faces the case because it only
/// exists while media does.
@MainActor
struct NowPlayingMenuSection: View {
    let coordinator: Coordinator

    var body: some View {
        Text(statusRow)
        // The gate reads the SAME value the row above is drawn from, and that
        // identity is the contract: a second predicate over the media state is how a
        // row saying "Nothing playing" ends up over an enabled Pause.
        //
        // It deliberately does NOT rise into MenuStatus with the rest of the menu's
        // gating. That type is built in CremaMenu's body, whose every rebuild
        // pull-reads the event-tap chain — a system-wide probe — and the media state
        // it would have to read is rewritten once a second, so the gate would buy
        // that probe a 1 Hz dependency. It belongs to the body that already reads
        // the mirrors, which is this one (docs/DECISIONS.md: menu-reads-mirrors).
        if mediaLine.namesMedia {
            Button(playPauseLabel) {
                coordinator.togglePlayPause()
            }
            .disabled(!transportEnabled)
            Button(String(localized: "transport.previousTrack", defaultValue: "Previous Track")) {
                coordinator.previousTrack()
            }
            .disabled(!skipEnabled)
            Button(String(localized: "transport.nextTrack", defaultValue: "Next Track")) {
                coordinator.nextTrack()
            }
            .disabled(!skipEnabled)
        }
    }

    /// The one read of the media state, feeding both the row and the gate.
    private var mediaLine: NowPlayingMenuLine {
        NowPlayingMenuLine(title: coordinator.nowPlayingTitle, artist: coordinator.nowPlayingArtist)
    }

    /// Media names are external content and stay verbatim (the StringProtocol
    /// overload of Text, so no markdown is parsed out of an artist's name); what is
    /// localized is the empty state and the composition joining the two names.
    private var statusRow: String {
        switch mediaLine {
        case .nothing:
            String(localized: "menu.nowPlaying.nothing", defaultValue: "Nothing playing")
        case .title(let title):
            title
        case let .titleAndArtist(title, artist):
            String(localized: "menu.nowPlaying.titleAndArtist", defaultValue: "\(title) — \(artist)")
        }
    }

    /// Play vs Pause off `mediaActive`, which flips only on a real play/pause edge —
    /// the live snapshot's `isPlaying` carries the same fact at the price of a
    /// rebuild per second. Same keys the surface's transport button will use for the
    /// accessibility label it still lacks: one name per concept.
    private var playPauseLabel: String {
        coordinator.mediaActive
            ? String(localized: "transport.pause", defaultValue: "Pause")
            : String(localized: "transport.play", defaultValue: "Play")
    }

    /// Paused media still commands — Play is what the user came for — so these are
    /// the Coordinator's verdicts and nothing else. The `namesMedia` half they used
    /// to carry moved up to the gate around the buttons: it decides whether the
    /// items EXIST, and a copy of it here would be a second reading of the same fact,
    /// still true only by accident the day one of them changes.
    private var transportEnabled: Bool {
        coordinator.commandsAvailable
    }

    private var skipEnabled: Bool {
        coordinator.skipControlsEnabled
    }
}
