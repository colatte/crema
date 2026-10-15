import Testing
@testable import Crema

/// Pure level→symbol mapping for the HUD. Mirrors the native OSD: mute and
/// silence are their own glyphs, the volume waves grow one per third, and the
/// two brightnesses split at the midpoint. Every boundary is pinned here
/// because the thresholds live in HUDPresentation, not in the SF Symbols
/// renderer — the same mapping the three styles and both Card variants show.
struct HUDPresentationTests {

    private func icon(
        _ kind: SystemHUD.Kind,
        _ value: Double,
        isMuted: Bool = false,
        route: AudioOutputRoute? = nil
    ) -> String {
        HUDPresentation(hud: SystemHUD(kind: kind, value: value, isMuted: isMuted, route: route)).iconSystemName
    }

    private let lowThird = 1.0 / 3.0
    private let highThird = 2.0 / 3.0

    // MARK: - Volume

    @Test func mutedShowsSlashRegardlessOfLevel() {
        #expect(icon(.volume, 0, isMuted: true) == "speaker.slash.fill")
        #expect(icon(.volume, 0.5, isMuted: true) == "speaker.slash.fill")
        #expect(icon(.volume, 1, isMuted: true) == "speaker.slash.fill")
    }

    @Test func zeroVolumeShowsBareSpeaker() {
        #expect(icon(.volume, 0) == "speaker.fill")
    }

    @Test func aboveZeroEntersFirstWave() {
        #expect(icon(.volume, 0.0.nextUp) == "speaker.wave.1.fill")
        #expect(icon(.volume, 0.1) == "speaker.wave.1.fill")
    }

    @Test func firstThirdBoundaryStaysWaveOne() {
        // Upper edge inclusive: exactly 1/3 keeps the lower step.
        #expect(icon(.volume, lowThird) == "speaker.wave.1.fill")
    }

    @Test func justPastFirstThirdEntersWaveTwo() {
        #expect(icon(.volume, lowThird.nextUp) == "speaker.wave.2.fill")
        #expect(icon(.volume, 0.5) == "speaker.wave.2.fill")
    }

    @Test func secondThirdBoundaryStaysWaveTwo() {
        #expect(icon(.volume, highThird) == "speaker.wave.2.fill")
    }

    @Test func justPastSecondThirdEntersWaveThree() {
        #expect(icon(.volume, highThird.nextUp) == "speaker.wave.3.fill")
        #expect(icon(.volume, 1) == "speaker.wave.3.fill")
    }

    // MARK: - Volume by output route

    /// Written apart from the production switch: the glyph each route owes.
    /// Nil is the speaker family, which still steps with the level.
    private let deviceGlyphs: [AudioOutputRoute: String?] = [
        .builtInSpeakers: nil,
        .unknown: nil,
        .wiredHeadphones: "headphones",
        .bluetoothHeadphones: "headphones",
        .airPods: "airpods",
        .airPodsPro: "airpodspro",
        .airPodsMax: "airpodsmax",
        .beats: "beats.headphones",
        .airPlay: "airplayaudio",
        .display: "display",
    ]

    @Test func everyRouteHasAnExpectedGlyph() {
        #expect(Set(deviceGlyphs.keys) == Set(AudioOutputRoute.allCases))
    }

    @Test(arguments: AudioOutputRoute.allCases)
    func aDeviceGlyphReplacesTheSpeakerAtEveryLevel(route: AudioOutputRoute) throws {
        let expected = try #require(deviceGlyphs[route])
        for value in [0, 0.2, 0.5, 1.0] {
            let shown = icon(.volume, value, route: route)
            if let expected {
                #expect(shown == expected, "\(route) at \(value)")
            } else {
                #expect(shown == icon(.volume, value), "\(route) at \(value)")
            }
        }
    }

    @Test(arguments: AudioOutputRoute.allCases)
    func muteKeepsTheSlashedSpeakerOnEveryDevice(route: AudioOutputRoute) {
        #expect(icon(.volume, 0.5, isMuted: true, route: route) == "speaker.slash.fill")
        #expect(icon(.volume, 0, isMuted: true, route: route) == "speaker.slash.fill")
    }

    @Test func theSpeakersAndAnUnknownDeviceKeepTheWaves() {
        for route: AudioOutputRoute? in [nil, .builtInSpeakers, .unknown] {
            #expect(icon(.volume, 0, route: route) == "speaker.fill")
            #expect(icon(.volume, 0.2, route: route) == "speaker.wave.1.fill")
            #expect(icon(.volume, 0.5, route: route) == "speaker.wave.2.fill")
            #expect(icon(.volume, 1, route: route) == "speaker.wave.3.fill")
        }
    }

    /// Every name the presentation can emit, each one available on macOS 14
    /// (the deployment floor), read from CoreGlyphs' `name_availability.plist`:
    /// the first macOS each name shipped in. A static list on purpose: a live
    /// image lookup would answer for the machine running the tests, not for
    /// the oldest one the app supports.
    private static let macOS14Glyphs: Set<String> = [
        "speaker.fill",          // 10.15
        "speaker.slash.fill",    // 10.15
        "speaker.wave.1.fill",   // 11.0
        "speaker.wave.2.fill",   // 11.0
        "speaker.wave.3.fill",   // 11.0
        "sun.min.fill",          // 10.15
        "sun.max.fill",          // 10.15
        "light.min",             // 10.15
        "light.max",             // 10.15
        "headphones",            // 10.15
        "airpods",               // 11.0
        "airpodspro",            // 11.0
        "airpodsmax",            // 11.3
        "beats.headphones",      // 12.0
        "airplayaudio",          // 10.15
        "display",               // 11.0
    ]

    @Test func everyEmittedGlyphExistsOnMacOS14() {
        let levels = [0, 0.0.nextUp, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.9, 1]
        let routes: [AudioOutputRoute?] = [nil] + AudioOutputRoute.allCases
        for kind in SystemHUD.Kind.allCases {
            for value in levels {
                for isMuted in [false, true] {
                    for route in routes {
                        let name = icon(kind, value, isMuted: isMuted, route: route)
                        #expect(Self.macOS14Glyphs.contains(name), "\(name) from \(kind) \(value) \(isMuted) \(String(describing: route))")
                    }
                }
            }
        }
    }

    @Test func brightnessIgnoresARoute() {
        #expect(icon(.screenBrightness, 1, route: .airPods) == "sun.max.fill")
        #expect(icon(.keyboardBrightness, 0, route: .airPods) == "light.min")
    }

    // MARK: - Screen brightness

    @Test func screenBrightnessSplitsAtMidpoint() {
        #expect(icon(.screenBrightness, 0) == "sun.min.fill")
        #expect(icon(.screenBrightness, 0.5.nextDown) == "sun.min.fill")
        #expect(icon(.screenBrightness, 0.5) == "sun.max.fill")
        #expect(icon(.screenBrightness, 1) == "sun.max.fill")
    }

    // MARK: - Keyboard brightness

    @Test func keyboardBrightnessSplitsAtMidpoint() {
        #expect(icon(.keyboardBrightness, 0) == "light.min")
        #expect(icon(.keyboardBrightness, 0.5.nextDown) == "light.min")
        #expect(icon(.keyboardBrightness, 0.5) == "light.max")
        #expect(icon(.keyboardBrightness, 1) == "light.max")
    }

    // MARK: - Value passthrough

    @Test func valueMirrorsTheEvent() {
        #expect(HUDPresentation(hud: SystemHUD(kind: .volume, value: 0.42)).value == 0.42)
    }
}
