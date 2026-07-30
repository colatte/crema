import SwiftUI

/// The menu's media group: what is playing, then the transport that acts on it.
///
/// A separate View for a load-bearing reason, not for tidiness: SwiftUI tracks
/// observation per BODY, so a track change repaints this one and leaves the scene
/// body — and MenuInformation — alone; a rebuild of that block costs a
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
/// media does and this menu exists always; it comes off the SAME value as the
/// status row (NowPlayingMenuLine.namesMedia) so the row and the buttons cannot
/// disagree. Items disable instead of disappearing, so the menu keeps its shape as
/// availability moves (the rule TransportControls follows for the same reason).
@MainActor
struct NowPlayingMenuSection: View {
    let coordinator: Coordinator

    var body: some View {
        Text(statusRow)
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

    /// Paused media still commands (Play is what the user came for); no media at
    /// all greys the three items in place, because `commandsAvailable` is optimistic
    /// by contract and would otherwise read enabled over silence.
    private var transportEnabled: Bool {
        mediaLine.namesMedia && coordinator.commandsAvailable
    }

    private var skipEnabled: Bool {
        mediaLine.namesMedia && coordinator.skipControlsEnabled
    }
}
