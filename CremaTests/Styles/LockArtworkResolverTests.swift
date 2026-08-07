import Testing
@testable import Crema

/// The resolver's whole contract, over a lookup that answers from a script.
///
/// Two invariants carry it. There is ALWAYS something to draw — the upgrade
/// improves the player's cover, it never stands in for having one. And bytes
/// never outlive the identity they belong to, which is the failure that would
/// be visible and wrong rather than merely absent: one album's cover on the
/// next song's surface.
@MainActor
struct LockArtworkResolverTests {

    private func track(
        _ title: String,
        artist: String? = "Yorushika",
        album: String? = "Algernon - Single",
        artwork: [UInt8]? = [1, 2, 3],
        position: Double = 0
    ) -> NowPlaying {
        NowPlaying(
            title: title, artist: artist, artworkData: artwork, album: album,
            isPlaying: true, position: position, duration: 200
        )
    }

    // MARK: - There is always something to draw

    @Test func beforeAnyAnswerItIsThePlayersOwnCover() {
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: [9, 9]), enabled: true)
        // The surface is drawn the instant the screen locks; waiting on a
        // network round trip to show a cover would be a blank square.
        #expect(resolver.artwork(for: track("Algernon")) == [1, 2, 3])
    }

    @Test func anAnswerUpgradesTheCover() async {
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: [9, 9]), enabled: true)
        let song = track("Algernon")
        await resolver.resolve(song)
        #expect(resolver.artwork(for: song) == [9, 9])
    }

    @Test func aLookupThatFindsNothingLeavesThePlayersCoverAlone() async {
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: nil), enabled: true)
        let song = track("Something Unreleased")
        await resolver.resolve(song)
        #expect(resolver.artwork(for: song) == [1, 2, 3])
    }

    @Test func aTrackWithNoCoverAtAllStaysWithNoneRatherThanBorrowing() async {
        // The JXA fallback carries no artwork. A resolver that answered with the
        // previous track's bytes here would put the wrong album on screen.
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: [9, 9]), enabled: true)
        let first = track("Algernon")
        await resolver.resolve(first)
        #expect(resolver.artwork(for: track("Live Radio", artwork: nil)) == nil)
    }

    // MARK: - Bytes never outlive their identity

    @Test func theUpgradeDoesNotFollowTheNextTrack() async {
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: [9, 9]), enabled: true)
        await resolver.resolve(track("Algernon"))
        #expect(resolver.artwork(for: track("Algernon")) == [9, 9])
        // A different song, not yet resolved: it must show ITS own cover, not
        // the one still held from the last request.
        #expect(resolver.artwork(for: track("Ghost", artwork: [7, 7])) == [7, 7])
    }

    @Test func thePositionTickIsTheSameTrackAndNeverReAsks() async {
        let lookup = MockArtworkLookup(answer: [9, 9])
        let resolver = LockArtworkResolver(lookup: lookup, enabled: true)
        // The snapshot is rewritten once a second by the position tick. Keying
        // on it rather than on the identity would hammer the endpoint at 1 Hz.
        await resolver.resolve(track("Algernon", position: 0))
        await resolver.resolve(track("Algernon", position: 1))
        await resolver.resolve(track("Algernon", position: 2))
        #expect(lookup.asked.count == 1)
    }

    @Test func theIdentityIsTheThreeTermsTheLookupSearchesOn() {
        let base = track("Algernon")
        #expect(LockArtworkResolver.identity(of: base) == LockArtworkResolver.identity(of: track("Algernon")))
        // A different album with the same title and artist is a different
        // cover, which is the whole reason `album` was added to the domain.
        #expect(LockArtworkResolver.identity(of: base)
            != LockArtworkResolver.identity(of: track("Algernon", album: "A Compilation")))
    }

    // MARK: - The preference

    @Test func disabledNeverAsks() async {
        let lookup = MockArtworkLookup(answer: [9, 9])
        let resolver = LockArtworkResolver(lookup: lookup, enabled: false)
        await resolver.resolve(track("Algernon"))
        // Off means no network at all — not a request whose answer is discarded.
        #expect(lookup.asked.isEmpty)
        #expect(resolver.artwork(for: track("Algernon")) == [1, 2, 3])
    }

    @Test func turningItOffDropsTheUpgradeAlreadyOnScreen() async {
        let resolver = LockArtworkResolver(lookup: MockArtworkLookup(answer: [9, 9]), enabled: true)
        let song = track("Algernon")
        await resolver.resolve(song)
        #expect(resolver.artwork(for: song) == [9, 9])

        resolver.setEnabled(false)
        // Switching it off is a request about now, not about the next track.
        #expect(resolver.artwork(for: song) == [1, 2, 3])
    }

    @Test func turningItOnStartsAskingWithoutWaitingForATrackChange() async {
        let lookup = MockArtworkLookup(answer: [9, 9])
        let resolver = LockArtworkResolver(lookup: lookup, enabled: false)
        let song = track("Algernon")
        await resolver.resolve(song)
        #expect(lookup.asked.isEmpty)

        resolver.setEnabled(true)
        await resolver.resolve(song)
        #expect(lookup.asked.count == 1)
        #expect(resolver.artwork(for: song) == [9, 9])
    }
}
