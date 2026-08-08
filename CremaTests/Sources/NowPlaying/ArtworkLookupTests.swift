import Testing
@testable import Crema

/// Whether something a cover endpoint returned is the record that is playing.
///
/// The rule exists because a search endpoint answers with the closest thing it
/// has rather than with nothing, so it cheerfully returns a song for a podcast
/// episode. Taking the top hit unchecked replaced correct artwork with an
/// unrelated album cover — and wrong art is worse than none, because the
/// fallback was already right.
struct ArtworkMatchTests {

    @Test func aPodcastEpisodeIsNotMatchedByWhateverSongComesBack() {
        // The failure this exists for. Nothing about the two titles agrees, and
        // the check has to say so rather than hand over an album cover.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Ep. 412 — The Housing Crisis, Revisited",
            requestedArtist: "Search Engine",
            resultTitle: "Crisis",
            resultArtist: "Alice Deejay"
        ))
    }

    @Test func theSameRecordingSurvivesTheEndpointsExtraTail() {
        // Remasters, live versions and feature credits live in the parenthetical
        // tail, and they are the same cover often enough to keep. Rejecting them
        // would make the feature miss most of its real hits.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon",
            requestedArtist: "Yorushika",
            resultTitle: "Algernon (Remastered 2023)",
            resultArtist: "Yorushika"
        ))
        // And in the other direction: the player carries the tail, not the
        // endpoint.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Breathe (In the Air)",
            requestedArtist: "Pink Floyd",
            resultTitle: "Breathe",
            resultArtist: "Pink Floyd"
        ))
    }

    @Test func caseAccentsAndPunctuationAreNotDisagreement() {
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Não Vá Embora",
            requestedArtist: "Tim Maia",
            resultTitle: "nao va embora",
            resultArtist: "TIM MAIA"
        ))
    }

    @Test func theRightSongByTheWrongArtistIsRefused() {
        // Covers and karaoke tracks are the common case, and they carry the
        // wrong art by definition.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Creep",
            requestedArtist: "Radiohead",
            resultTitle: "Creep",
            resultArtist: "Karaoke Kings"
        ))
    }

    @Test func aTrackWithNoArtistIsJudgedOnItsTitleAlone() {
        // The JXA fallback frequently reports no artist. Refusing every lookup
        // for those would turn a missing field into a missing feature.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: nil,
            resultTitle: "Algernon", resultArtist: "Yorushika"
        ))
        #expect(ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: "",
            resultTitle: "Algernon", resultArtist: "Yorushika"
        ))
    }

    @Test func anAnswerThatNamesNothingIsNoEvidence() {
        // A result with no title cannot be shown to agree with anything, and
        // absence must never read as assent.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Algernon", requestedArtist: "Yorushika",
            resultTitle: nil, resultArtist: "Yorushika"
        ))
        // And a title that normalizes to nothing — punctuation only — must not
        // become an empty string that "contains" every other string.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "!!!", requestedArtist: nil,
            resultTitle: "Algernon", resultArtist: nil
        ))
    }

    @Test func anAlbumIsJudgedByTheSameRule() {
        // The rule judges a name against a name, which is what let the release
        // group's title reuse it unchanged when the cover source moved off a
        // per-track endpoint onto a per-record one.
        #expect(ArtworkMatch.plausible(
            requestedTitle: "The Dark Side of the Moon", requestedArtist: "Pink Floyd",
            resultTitle: "The Dark Side of the Moon", resultArtist: "Pink Floyd"
        ))
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "The Dark Side of the Moon", requestedArtist: "Pink Floyd",
            resultTitle: "The Wall", resultArtist: "Pink Floyd"
        ))
    }
}

/// The hole a mutation opened up in the first version of `agrees`.
///
/// Plain containment accepted any short song title that appeared ANYWHERE in a
/// long one. The podcast case only failed because its artist disagreed too, so
/// the title check was carrying none of the weight it looked like it carried.
struct ArtworkMatchAnchoringTests {

    @Test func aSongTitleBuriedInsideALongerOneIsNotAMatch() {
        // The exact pair the mutation surfaced, minus the artist that was
        // secretly doing the work.
        #expect(!ArtworkMatch.plausible(
            requestedTitle: "Ep. 412 — The Housing Crisis, Revisited",
            requestedArtist: nil,
            resultTitle: "Crisis",
            resultArtist: nil
        ))
    }

    @Test func aPrefixThatIsNotAWholeWordIsNotAMatch() {
        // "Love" must not match "Lovesong": different record, different art.
        #expect(!ArtworkMatch.agrees("Lovesong", "Love"))
        #expect(!ArtworkMatch.agrees("Love", "Lovesong"))
    }

    @Test func aTailIsStillTolerated() {
        // What containment was actually there for, and all of it survives.
        #expect(ArtworkMatch.agrees("Algernon", "Algernon feat. Someone"))
        #expect(ArtworkMatch.agrees("Algernon - Remastered", "Algernon"))
        #expect(ArtworkMatch.agrees("Breathe (In the Air)", "Breathe"))
    }
}
