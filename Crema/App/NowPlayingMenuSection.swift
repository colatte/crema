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
/// Availability is rendered here, never decided here: `controlsEnabled` and
/// `skipControlsEnabled` are the Coordinator's verdicts, the same two the
/// surface's transport binds to (SurfaceStyleBody) — one decision, two renderers.
/// Only "is there media at all" is added, because the surface exists only when
/// media does and this menu exists always.
///
/// The two questions are answered differently on purpose. A command the player
/// REFUSED greys its item in place, so the section keeps its shape as availability
/// moves (the rule TransportControls follows for the same reason). Media that does
/// not exist takes the whole section away instead, title included: there is no
/// object to act on, and a line saying nothing is playing is the one part of a
/// menu no user can ever use — the surface never faces the case because it only
/// exists while media does.
@MainActor
struct NowPlayingMenuSection: View {
    let coordinator: Coordinator

    var body: some View {
        // The gate IS the row: the section exists exactly when there is a line
        // naming media, so a title over nothing, or a transport under nothing,
        // cannot be built. A second predicate over the media state is how a row
        // naming nothing ends up over an enabled Pause.
        //
        // It deliberately does NOT rise into MenuStatus with the rest of the menu's
        // gating. That type is built in CremaMenu's body, whose every rebuild
        // pull-reads the event-tap chain — a system-wide probe — and the media state
        // it would have to read is rewritten once a second, so the gate would buy
        // that probe a 1 Hz dependency. It belongs to the body that already reads
        // the mirrors, which is this one (docs/DECISIONS.md: menu-reads-mirrors).
        if let row = statusRow {
            // Titled with the Now Playing tab's own name: one concept, one name.
            Section(String(localized: "menu.section.nowPlaying", defaultValue: "Now Playing")) {
                Text(row)
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
    }

    /// The one read of the media state, feeding the row and, through it, the gate.
    private var mediaLine: NowPlayingMenuLine {
        NowPlayingMenuLine(title: coordinator.nowPlayingTitle, artist: coordinator.nowPlayingArtist)
    }

    /// The line naming the media, or nil when there is none. Media names are
    /// external content and stay verbatim (the StringProtocol overload of Text, so no
    /// markdown is parsed out of an artist's name); what is localized is the
    /// composition joining the two names.
    private var statusRow: String? {
        switch mediaLine {
        case .nothing:
            nil
        case .title(let title):
            Self.fitted(title)
        case let .titleAndArtist(title, artist):
            Self.fitted(String(localized: "menu.nowPlaying.titleAndArtist", defaultValue: "\(title) — \(artist)"))
        }
    }

    /// The menu's line ceiling. An NSMenu is as wide as its widest item, and a
    /// title is whatever the player published, so a row past this would open the
    /// whole menu across the screen (docs/DECISIONS.md: menu-status-before-warnings).
    nonisolated static let lineCeiling = 72

    /// The row as it fits: cut at the ceiling, with an ellipsis standing for the rest.
    nonisolated static func fitted(_ row: String) -> String {
        row.count <= lineCeiling ? row : String(row.prefix(lineCeiling - 1)) + "…"
    }

    /// Play vs Pause off `mediaActive`, which flips only on a real play/pause edge —
    /// the live snapshot's `isPlaying` carries the same fact at the price of a
    /// rebuild per second. The same two keys the surface's transport button speaks
    /// its accessibility label from: one name per concept, so the menu item and the
    /// button VoiceOver reads are never two different verbs for one command.
    private var playPauseLabel: String {
        coordinator.mediaActive
            ? String(localized: "transport.pause", defaultValue: "Pause")
            : String(localized: "transport.play", defaultValue: "Play")
    }

    /// Paused media still commands — Play is what the user came for — so these are
    /// the Coordinator's verdicts and nothing else. Whether the items EXIST is the
    /// gate around the buttons, and a copy of that fact here would be a second
    /// reading of it, still true only by accident the day one of them changes.
    private var transportEnabled: Bool {
        coordinator.controlsEnabled
    }

    private var skipEnabled: Bool {
        coordinator.skipControlsEnabled
    }
}
