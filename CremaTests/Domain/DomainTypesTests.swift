import Testing
@testable import Crema

struct DomainTypesTests {

    private let track = NowPlaying(
        title: "Breathe",
        artist: "Pink Floyd",
        isPlaying: true,
        position: 42.0,
        duration: 169.0
    )

    @Test func nowPlayingIsAValueTypeWithEquality() {
        var copy = track
        #expect(copy == track)
        copy.position = 43.0
        #expect(copy != track)
    }

    @Test func nowPlayingCarriesScrubbingAndPlaybackData() {
        #expect(track.position == 42.0)
        #expect(track.duration == 169.0)
        #expect(track.isPlaying)
    }

    @Test func nowPlayingDurationIsOptionalForLiveContent() {
        let live = NowPlaying(title: "Some Radio", isPlaying: true, position: 0)
        #expect(live.duration == nil)
    }

    @Test func systemHUDDefaultsToInternalDisplayAndUnmuted() {
        let hud = SystemHUD(kind: .volume, value: 0.5)
        #expect(hud.display == nil)
        #expect(!hud.isMuted)
    }

    @Test func systemHUDCoversVolumeAndBothBrightnessKinds() {
        #expect(SystemHUD.Kind.allCases == [.volume, .screenBrightness, .keyboardBrightness])
    }

    @Test func systemHUDCanBeAssociatedToADisplayByUUID() {
        let uuid = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        let external = SystemHUD(kind: .screenBrightness, value: 0.8, display: uuid)
        #expect(external.display == uuid)
        #expect(external != SystemHUD(kind: .screenBrightness, value: 0.8))
    }

    @Test func presentationStateRepresentsAllDistinctStates() {
        let hud = SystemHUD(kind: .volume, value: 0.5)
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(hud),
        ]
        for (i, a) in states.enumerated() {
            for (j, b) in states.enumerated() where i != j {
                #expect(a != b)
            }
        }
    }

    @Test func presentationStateDistinguishesCompactFromExpanded() {
        #expect(PresentationState.nowPlaying(track, expanded: true) != .nowPlaying(track, expanded: false))
    }

    @Test func domainTypesAreSendable() {
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(NowPlaying.self)
        requireSendable(SystemHUD.self)
        requireSendable(PresentationState.self)
        requireSendable(DisplayUUID.self)
        #expect(Bool(true))
    }
}
