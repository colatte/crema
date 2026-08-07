import Foundation
import Testing
@testable import Crema

// The JSON fixtures below are single long lines by nature.
// swiftlint:disable line_length

/// Translation of the adapter's JSON lines into NowPlaying, with real
/// fixtures from the observed format (type/diff/payload).
struct AdapterPayloadTranslationTests {

    // A real line from the smoke test (artwork stripped there via --no-artwork).
    private let fullLine = #"""
    {"type":"data","diff":false,"payload":{"artist":"Pink Floyd","playbackRate":1,"title":"Breathe","elapsedTime":42.5,"duration":169.0,"playing":true,"bundleIdentifier":"com.spotify.client","album":"The Dark Side of the Moon","timestamp":"2026-07-04T19:14:19Z"}}
    """#

    /// `.distantPast` predates any fixture anchor, so the aging clamps to zero
    /// and every test below reads the anchor raw unless it opts into a `now`.
    private func translate(_ line: String, at now: Date = .distantPast) -> NowPlaying? {
        AdapterPayloadTranslation.nowPlaying(fromLine: line, at: now)
    }

    @Test func translatesAFullPayload() throws {
        let np = try #require(translate(fullLine))
        #expect(np.title == "Breathe")
        #expect(np.artist == "Pink Floyd")
        #expect(np.isPlaying)
        #expect(np.position == 42.5)
        #expect(np.duration == 169.0)
        #expect(np.artworkData == nil)
        #expect(np.album == "The Dark Side of the Moon")
        #expect(np.sourceBundleID == "com.spotify.client")
    }

    @Test func aMissingOrEmptyAlbumIsNilRatherThanABlankSearchTerm() throws {
        // Its only reader is the cover lookup, which joins the terms into a query
        // — an empty string there is not a narrower search, it is a worse one.
        let missing = #"{"type":"data","diff":false,"payload":{"title":"Solo","playing":true,"elapsedTime":0,"duration":100}}"#
        let blank = #"{"type":"data","diff":false,"payload":{"title":"Solo","album":"","playing":true,"elapsedTime":0,"duration":100}}"#
        #expect(try #require(translate(missing)).album == nil)
        #expect(try #require(translate(blank)).album == nil)
    }

    @Test func parentBundleIdentifierWinsOverTheHelperProcess() throws {
        // Browsers play through WebKit helpers: the payload's bundleIdentifier
        // is the helper, the parent is the real app — the browser filter must
        // see the browser.
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":1,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari"}}"#
        let np = try #require(translate(line))
        #expect(np.sourceBundleID == "com.apple.Safari")
    }

    @Test func missingBundleIdentifiersLeaveTheSourceUnknown() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":1}}"#
        let np = try #require(translate(line))
        #expect(np.sourceBundleID == nil)
    }

    @Test func playingFalseBecomesIsPlayingFalse() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":false,"elapsedTime":1,"duration":10}}"#
        let np = try #require(translate(line))
        #expect(!np.isPlaying)
    }

    @Test func emptyPayloadMeansNothingPlaying() {
        #expect(translate(#"{"type":"data","diff":false,"payload":{}}"#) == nil)
    }

    @Test func missingArtistIsNil() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Solo","playing":true,"elapsedTime":0,"duration":100}}"#
        let np = try #require(translate(line))
        #expect(np.artist == nil)
    }

    @Test func emptyArtistStringIsNil() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Solo","artist":"","playing":true,"elapsedTime":0,"duration":100}}"#
        let np = try #require(translate(line))
        #expect(np.artist == nil)
    }

    @Test func missingOrZeroDurationIsNilForLiveContent() throws {
        let missing = #"{"type":"data","diff":false,"payload":{"title":"Radio","playing":true,"elapsedTime":5}}"#
        let zero = #"{"type":"data","diff":false,"payload":{"title":"Radio","playing":true,"elapsedTime":5,"duration":0}}"#
        #expect(try #require(translate(missing)).duration == nil)
        #expect(try #require(translate(zero)).duration == nil)
    }

    /// The line is verbatim from the wire: a Twitch live in Firefox, captured
    /// from the vendored adapter. Live content does not omit the duration — it
    /// reports LLONG_MAX microseconds, which the old `> 0` test waved through as
    /// 292 thousand years. Letting it through gave the scrubber a fake range to
    /// drag over, and dragging to the end scaled it back up to exactly 2^63,
    /// where `Int(Double)` traps: the app died on a normal gesture.
    @Test func theLiveSentinelDurationIsNotADuration() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Live","playing":true,"elapsedTimeMicros":2741906069,"durationMicros":9.2233720368547758e+18}}"#
        let np = try #require(translate(line))
        #expect(np.duration == nil)
    }

    @Test func anImplausiblyLongDurationIsRejectedInEitherUnit() throws {
        let micros = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":5,"durationMicros":9.0e+16}}"#
        let seconds = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":5,"duration":90000}}"#
        #expect(try #require(translate(micros)).duration == nil)
        #expect(try #require(translate(seconds)).duration == nil)
    }

    /// A sentinel duration must not clamp the position either — the aged
    /// position is the honest number, and clamping to garbage is still garbage.
    @Test func theLiveSentinelDoesNotClampThePosition() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"Live","playing":false,"elapsedTime":42,"durationMicros":9.2233720368547758e+18}}"#
        #expect(try #require(translate(line)).position == 42)
    }

    @Test func missingElapsedTimeDefaultsToZero() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"duration":10}}"#
        #expect(try #require(translate(line)).position == 0)
    }

    @Test func prohibitsSkipMapsToSupportsSkipFalse() throws {
        // Radio/live media swallows a delivered skip without an error, so this
        // metadata is the only signal the skip controls must disable on.
        let line = #"{"type":"data","diff":false,"payload":{"title":"Radio","playing":true,"elapsedTime":5,"prohibitsSkip":true}}"#
        #expect(try #require(translate(line)).supportsSkip == false)
    }

    @Test func absentOrFalseProhibitsSkipMeansSkippable() throws {
        let explicit = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":1,"prohibitsSkip":false}}"#
        #expect(try #require(translate(explicit)).supportsSkip)
        #expect(try #require(translate(fullLine)).supportsSkip)
    }

    @Test func decodesBase64Artwork() throws {
        // "AQID" == bytes [1, 2, 3]
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":0,"duration":10,"artworkData":"AQID"}}"#
        let np = try #require(translate(line))
        #expect(np.artworkData == [1, 2, 3])
    }

    @Test func nonDataOrGarbageLinesTranslateToNil() {
        #expect(translate(#"{"type":"error","message":"nope"}"#) == nil)
        #expect(translate("not json at all") == nil)
        #expect(translate("") == nil)
    }

    // MARK: - Anchor aging (the play/pause desync fix)

    /// Epoch second 1_000_000 as micros — the anchor instant of the lines below.
    private var anchorInstant: Date { Date(timeIntervalSince1970: 1_000_000) }

    private func anchoredLine(_ payloadExtras: String = "") -> String {
        #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTimeMicros":42500000,"durationMicros":169000000,"timestampEpochMicros":1000000000000\#(payloadExtras)}}"#
    }

    @Test func aPlayingAnchorAgesToDeliveryTime() throws {
        let np = try #require(translate(anchoredLine(), at: anchorInstant.addingTimeInterval(10)))
        #expect(np.position == 52.5)
    }

    @Test func aPausedAnchorDoesNotAge() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":false,"elapsedTimeMicros":42500000,"timestampEpochMicros":1000000000000}}"#
        let np = try #require(translate(line, at: anchorInstant.addingTimeInterval(10)))
        #expect(np.position == 42.5)
    }

    @Test func playbackRateScalesTheAging() throws {
        let np = try #require(translate(anchoredLine(#","playbackRate":2"#), at: anchorInstant.addingTimeInterval(10)))
        #expect(np.position == 62.5)
    }

    @Test func aFutureDatedAnchorDoesNotRewind() throws {
        let np = try #require(translate(anchoredLine(), at: anchorInstant.addingTimeInterval(-5)))
        #expect(np.position == 42.5)
    }

    @Test func agingClampsToTheDuration() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTimeMicros":165000000,"durationMicros":169000000,"timestampEpochMicros":1000000000000}}"#
        let np = try #require(translate(line, at: anchorInstant.addingTimeInterval(10)))
        #expect(np.position == 169)
    }

    @Test func microsKeysMapToSeconds() throws {
        let np = try #require(translate(anchoredLine(), at: anchorInstant))
        #expect(np.position == 42.5)
        #expect(np.duration == 169)
    }

    @Test func aTimestampWithoutAnElapsedKeyDoesNotFabricateAPosition() throws {
        // Aging a defaulted 0 would invent minutes of playback for payloads
        // that carry a timestamp but no elapsed time (and live content has no
        // duration to clamp the invention).
        let line = #"{"type":"data","diff":false,"payload":{"title":"Radio","playing":true,"timestampEpochMicros":1000000000000}}"#
        let np = try #require(translate(line, at: anchorInstant.addingTimeInterval(600)))
        #expect(np.position == 0)
    }

    @Test func anAnchorWithoutATimestampReadsRaw() throws {
        let line = #"{"type":"data","diff":false,"payload":{"title":"X","playing":true,"elapsedTime":42.5}}"#
        let np = try #require(translate(line, at: anchorInstant.addingTimeInterval(10)))
        #expect(np.position == 42.5)
    }

    @Test func theISOTimestampIsTheFallbackAnchor() throws {
        // fullLine carries the second-based keys; its ISO timestamp still ages.
        let anchor = try #require(ISO8601DateFormatter().date(from: "2026-07-04T19:14:19Z"))
        let np = try #require(translate(fullLine, at: anchor.addingTimeInterval(10)))
        #expect(np.position == 52.5)
    }
}

// swiftlint:enable line_length
