import Foundation

/// Capability: a larger cover than the player handed over.
///
/// The adapter passes on whatever bitmap the player published — typically
/// 300–600 px, and not negotiable: `MRMediaRemoteGetNowPlayingInfo` takes no
/// options dictionary, so there is no size to ask for and the dimensions
/// received are not even reported. Fine behind a 50 pt thumbnail. Visibly soft
/// as a 300 pt cover filling a lock screen. On the JXA fallback there is no
/// bitmap at all, and then this is the only cover there will ever be.
///
/// A capability rather than a function because the honest answer is usually
/// "no": no match, no network, feature off. Every one of those is silence, and
/// the surface must be complete without it.
///
/// It is also the seam that made changing cover sources cheap. The shipped
/// conformer is `CoverArtArchiveLookup`; the one before it went out over Apple's
/// search endpoint and was retired on its licence terms rather than on its
/// behaviour (docs/DECISIONS.md: the-cover-comes-from-the-archive-not-the-store).
protocol ArtworkLookup: Sendable {
    /// Nil for every failure, and they are all the same failure to the caller:
    /// the widget falls back to the bytes it already has.
    func highResolutionArtwork(title: String, artist: String?, album: String?) async -> [UInt8]?
}

/// Whether something a cover endpoint returned is plausibly what is playing.
///
/// Pure and separate because it is the whole judgement, and because the
/// alternative — trusting the endpoint's top hit — has specific victims. A
/// search endpoint answers with the closest thing it has, not with nothing: a
/// podcast episode, an audiobook chapter or a live stream, each carrying correct
/// artwork of its own, would have it replaced by an unrelated album cover. Wrong
/// art is worse than none, because the fallback was already right.
///
/// The bar is deliberately generous, not exact: the goal is to reject the
/// unrelated, not to demand the identical. It judges a name against a name, so
/// the same rule serves a track title, an album title and a release group's.
enum ArtworkMatch {
    /// Case, accents, punctuation and the parenthetical tail all removed —
    /// "Algernon (Remastered 2023)" and "algernon" have to meet. The tail is
    /// where remasters, live versions and feature credits live, and they are
    /// the same recording's cover often enough to keep.
    static func normalized(_ value: String) -> String {
        let withoutTail = value.replacingOccurrences(
            of: #"[\(\[].*?[\)\]]"#, with: " ", options: .regularExpression
        )
        let folded = withoutTail.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let letters = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(letters).split(separator: " ").joined(separator: " ")
    }

    /// Equal after normalizing, or one a PREFIX of the other at a word boundary.
    ///
    /// Prefix rather than containment anywhere, and the difference is not
    /// theoretical — a mutation found it. Plain containment accepted "Crisis"
    /// for a podcast episode called "Ep. 412 — The Housing Crisis, Revisited",
    /// because the long title happens to contain the short one. Only the artist
    /// check was refusing that result, so a podcast reporting no artist would
    /// have taken a stranger's album cover.
    ///
    /// Prefix keeps every case containment was there for: what the two sides
    /// disagree about is a TAIL — " feat. X", " - Remastered", " - Single" — and
    /// a tail is exactly what a prefix tolerates. Empty on either side is no
    /// evidence, so it can never be the thing that accepts a result.
    static func agrees(_ requested: String, _ found: String?) -> Bool {
        let want = normalized(requested)
        guard let found, !want.isEmpty else { return false }
        let got = normalized(found)
        guard !got.isEmpty else { return false }
        if want == got { return true }
        let (shorter, longer) = want.count < got.count ? (want, got) : (got, want)
        // The boundary matters: without it "Love" would be a prefix of
        // "Lovesong", which is a different record with different art.
        return longer.hasPrefix(shorter + " ")
    }

    /// The title must agree. The artist only has to agree when BOTH sides named
    /// one — the JXA fallback often reports no artist, and refusing every lookup
    /// for those tracks would turn a missing field into a missing feature.
    static func plausible(
        requestedTitle: String,
        requestedArtist: String?,
        resultTitle: String?,
        resultArtist: String?
    ) -> Bool {
        guard agrees(requestedTitle, resultTitle) else { return false }
        guard let requestedArtist, !requestedArtist.isEmpty, resultArtist?.isEmpty == false else {
            return true
        }
        return agrees(requestedArtist, resultArtist)
    }
}
