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
/// UNRESOLVED, and measured rather than assumed: `thePositionTickTouchesNeitherMirror`
/// does NOT detect the mutation it looks like it detects. Replace the comparing
/// guard in `Coordinator.publishTrackNames` with an unconditional
///
///     nowPlayingTitle = title
///     nowPlayingArtist = artist
///
/// and this suite stays green. Inverting the assertion to `#expect(namesChanged.value)`
/// under that mutation shows why: the flag is still FALSE, so no notification fires
/// for the same-value write at all — which contradicts the reasoning written on the
/// mirrors' own declaration, that Observation invalidates per property and not per
/// value. Either that reasoning is wrong (and the guard is decoration), or the tick
/// does not reach the writer in this harness (and the test proves nothing about the
/// tick). The guard stays either way, because it costs nothing and the failure it
/// guards against is a 1 Hz system-wide tap probe — but nobody should read this file
/// as proof that it works until that is settled.
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
