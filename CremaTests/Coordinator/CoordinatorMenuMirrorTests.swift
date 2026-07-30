import Observation
import Testing
@testable import Crema

/// The menu bar names the track through mirrors, and the mirrors are only worth
/// something if the position tick leaves them alone: the menu's status block
/// pull-reads the event-tap chain (AppCore.mediaKeyChainNotice(), which resets
/// every tap's latency stats on the machine), so a mirror that fired once per
/// second would turn a menu line into a 1 Hz system probe. Both directions are
/// pinned here — a guard that compares is one keystroke from a muzzle that never
/// writes (docs/DECISIONS.md: menu-reads-mirrors).
///
/// SETTLED, by measurement, and the answer was the first of the two possibilities
/// this note used to leave open.
///
/// `thePositionTickTouchesNeitherMirror` does not detect the removal of the
/// comparing guard in `Coordinator.publishTrackNames`, and that is correct rather
/// than defective: the tick DOES reach the writer (Coordinator publishes the names
/// on every update, ahead of every early return), and a write of an equal value
/// simply invalidates nothing. Measured directly on Swift 6.3.3 with a throwaway
/// @Observable subject: tracking one property, an equal-value write fired no
/// onChange, an unequal one fired. So the guard is not what keeps the tick quiet —
/// the runtime is — and no test can separate the two.
///
/// What this suite therefore pins is the CONTRACT, not the mechanism: the tick
/// leaves the mirrors alone, a real track change does not, and discarding the media
/// clears them. All three are what the menu depends on. The guard stays for the
/// reason written at `publishTrackNames`: the protection would otherwise rest on an
/// optimization inside Observation that no Apple document promises.
@MainActor
struct CoordinatorMenuMirrorTests {

    @Test func aTrackChangePublishesTitleAndArtist() async {
        let h = CoordinatorHarness()

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Breathe"))

        #expect(await eventually { h.coordinator.nowPlayingTitle == "Breathe" })
        #expect(h.coordinator.nowPlayingArtist == "Pink Floyd")
    }

    @Test func aTrackWithoutAnArtistPublishesNoArtist() async {
        let h = CoordinatorHarness()
        var solo = CoordinatorHarness.playingTrack(title: "Untitled")
        solo.artist = nil

        h.nowPlayingSource.emit(solo)

        #expect(await eventually { h.coordinator.nowPlayingTitle == "Untitled" })
        #expect(h.coordinator.nowPlayingArtist == nil)
    }

    @Test func thePositionTickTouchesNeitherMirror() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { h.coordinator.nowPlayingTitle == "Breathe" })

        let namesChanged = Flag()
        withObservationTracking {
            _ = h.coordinator.nowPlayingTitle
            _ = h.coordinator.nowPlayingArtist
        } onChange: {
            namesChanged.value = true
        }

        // Same track, one second later: the 1 Hz tick, which must not invalidate
        // anything the menu observes.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))

        #expect(await eventually { h.coordinator.nowPlaying?.position == 11 })
        await settle()
        #expect(!namesChanged.value)
    }

    @Test func aRealTrackChangeDoesInvalidateTheMirrors() async {
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Breathe"))
        #expect(await eventually { h.coordinator.nowPlayingTitle == "Breathe" })

        let namesChanged = Flag()
        withObservationTracking {
            _ = h.coordinator.nowPlayingTitle
            _ = h.coordinator.nowPlayingArtist
        } onChange: {
            namesChanged.value = true
        }

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(title: "Time"))

        #expect(await eventually { namesChanged.value })
        #expect(await eventually { h.coordinator.nowPlayingTitle == "Time" })
    }

    @Test func discardingTheMediaClearsTheMirrors() async {
        // The ghost-discard obligation reaches the menu too: a row still naming dead
        // media would sit above a transport that reads enabled.
        let h = CoordinatorHarness()
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.coordinator.nowPlayingTitle != nil })

        h.coordinator.activeNowPlayingSourceEnded()

        #expect(h.coordinator.nowPlayingTitle == nil)
        #expect(h.coordinator.nowPlayingArtist == nil)
    }
}
