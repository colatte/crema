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

    @Test func nowPlayingDurationIsOptionalForLiveContent() {
        let live = NowPlaying(title: "Some Radio", isPlaying: true, position: 0)
        #expect(live.duration == nil)
    }

    @Test func trackIdentityIsTitleAndArtist() {
        // One rule read by the surfacing thresholds and the scrub grace alike.
        #expect(track.isAnotherTrack(than: nil))
        var sameTrack = track
        sameTrack.isPlaying = false
        sameTrack.position = 100
        sameTrack.artworkData = [1, 2, 3]
        #expect(!sameTrack.isAnotherTrack(than: track))
        var retitled = track
        retitled.title = "Time"
        #expect(retitled.isAnotherTrack(than: track))
        var otherArtist = track
        otherArtist.artist = nil
        #expect(otherArtist.isAnotherTrack(than: track))
    }

    @Test func systemHUDDefaultsToNoDisplayAndUnmuted() {
        let hud = SystemHUD(kind: .volume, value: 0.5)
        #expect(hud.target == .noDisplay)
        #expect(hud.commandDisplay == nil)
        #expect(!hud.isMuted)
        #expect(hud.route == nil)
    }

    @Test func everyCopyOfAReadingKeepsItsRoute() {
        // The echo of a drag is a copy of the reading; losing the route there
        // would swap the device glyph back to the speaker under the finger.
        let hud = SystemHUD(kind: .volume, value: 0.5, route: .airPodsMax)
        #expect(hud.at(0.2).route == .airPodsMax)
        #expect(hud.by(.betterDisplay).route == .airPodsMax)
        #expect(hud.echoed().route == .airPodsMax)
        #expect(hud != SystemHUD(kind: .volume, value: 0.5))
    }

    @Test func systemHUDCoversVolumeAndBothBrightnessKinds() {
        #expect(SystemHUD.Kind.allCases == [.volume, .screenBrightness, .keyboardBrightness])
    }

    @Test func systemHUDCanBeAssociatedToADisplayByUUID() {
        let uuid = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
        let external = SystemHUD(kind: .screenBrightness, value: 0.8, target: .display(uuid))
        #expect(external.target == .display(uuid))
        #expect(external.commandDisplay == uuid)
        #expect(external != SystemHUD(kind: .screenBrightness, value: 0.8))
    }

    @Test func theBuiltInPanelIsARoleDistinctFromNamingNoDisplay() {
        // Two different facts a bare `DisplayUUID?` folds into one nil: no screen
        // owns this reading, versus the internal panel owns it. Only the second
        // scopes the bar, so the values must NOT compare equal or presentation
        // could not tell them apart. Actuation still sees nil for both, because
        // every actuator already reads nil as "my own panel"
        // (docs/DECISIONS.md: hud-target-is-a-role).
        let builtIn = SystemHUD(kind: .screenBrightness, value: 0.4, target: .builtIn)
        #expect(builtIn.commandDisplay == nil)
        #expect(builtIn != SystemHUD(kind: .screenBrightness, value: 0.4))
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
        // The real check is the compile-time requireSendable constraint below:
        // the domain must stay Sendable to cross threads. Losing it fails the
        // build, not this assertion — the #expect is a vestigial runtime line.
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(NowPlaying.self)
        requireSendable(SystemHUD.self)
        requireSendable(PresentationState.self)
        requireSendable(DisplayUUID.self)
        requireSendable(AudioOutputRoute.self)
        #expect(Bool(true))
    }
}
