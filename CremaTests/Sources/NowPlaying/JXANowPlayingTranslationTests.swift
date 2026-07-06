import Testing
@testable import Crema

/// Translation of the JXA probe's JSON output into NowPlaying. The JXA
/// script (Spotify/Music via scripting) is border/smoke; this is the pure part.
struct JXANowPlayingTranslationTests {

    @Test func translatesAPlayingTrack() throws {
        let json = #"{"title":"Breathe","artist":"Pink Floyd","duration":169.0,"position":42.0,"playing":true}"#
        let np = try #require(JXANowPlayingTranslation.nowPlaying(fromJSON: json))
        #expect(np.title == "Breathe")
        #expect(np.artist == "Pink Floyd")
        #expect(np.duration == 169.0)
        #expect(np.position == 42.0)
        #expect(np.isPlaying)
        #expect(np.artworkData == nil)   // JXA fallback carries no artwork
    }

    @Test func pausedTrackIsNotPlaying() throws {
        let json = #"{"title":"X","artist":"Y","duration":10,"position":1,"playing":false}"#
        #expect(try #require(JXANowPlayingTranslation.nowPlaying(fromJSON: json)).isPlaying == false)
    }

    @Test func emptyObjectMeansNothingPlaying() {
        #expect(JXANowPlayingTranslation.nowPlaying(fromJSON: "{}") == nil)
    }

    @Test func emptyArtistAndMissingDurationHandled() throws {
        let json = #"{"title":"Live","artist":"","position":5,"playing":true}"#
        let np = try #require(JXANowPlayingTranslation.nowPlaying(fromJSON: json))
        #expect(np.artist == nil)
        #expect(np.duration == nil)
    }

    @Test func garbageOrEmptyStringIsNil() {
        #expect(JXANowPlayingTranslation.nowPlaying(fromJSON: "not json") == nil)
        #expect(JXANowPlayingTranslation.nowPlaying(fromJSON: "") == nil)
    }
}
