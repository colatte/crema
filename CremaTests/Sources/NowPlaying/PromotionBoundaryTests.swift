import Testing
@testable import Crema

/// The pure predicate that gates a promotion to a quiet boundary
/// (docs/DECISIONS.md: promotion-quiet-boundary) — the logic extracted from the
/// chain so it is testable without a running source.
struct PromotionBoundaryTests {

    private func track(_ title: String, artist: String? = nil, playing: Bool = true) -> NowPlaying {
        NowPlaying(title: title, artist: artist, isPlaying: playing, position: 0, duration: 100)
    }

    @Test func aPauseIsAQuietBoundary() {
        #expect(PromotionBoundary.isQuiet(track("A", playing: false), previous: track("A")))
    }

    @Test func aStoppedFirstSnapshotIsAQuietBoundary() {
        #expect(PromotionBoundary.isQuiet(track("A", playing: false), previous: nil))
    }

    @Test func aTrackChangeWhilePlayingIsAQuietBoundary() {
        #expect(PromotionBoundary.isQuiet(track("B"), previous: track("A")))
    }

    @Test func anArtistChangeWhilePlayingIsAQuietBoundary() {
        #expect(PromotionBoundary.isQuiet(track("A", artist: "Two"), previous: track("A", artist: "One")))
    }

    @Test func theSameTrackStillPlayingIsNotABoundary() {
        #expect(!PromotionBoundary.isQuiet(track("A"), previous: track("A")))
    }

    @Test func theFirstPlayingEmissionIsNotABoundary() {
        // Mid-track with no prior identity: cutting over would flicker the
        // surface the user is already watching.
        #expect(!PromotionBoundary.isQuiet(track("A"), previous: nil))
    }
}
