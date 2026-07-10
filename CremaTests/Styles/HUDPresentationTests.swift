import Testing
@testable import Crema

/// Pure level→symbol mapping for the HUD. Mirrors the native OSD: mute and
/// silence are their own glyphs, the volume waves grow one per third, and the
/// two brightnesses split at the midpoint. Every boundary is pinned here
/// because the thresholds live in HUDPresentation, not in the SF Symbols
/// renderer — the same mapping the three styles and both Card variants show.
struct HUDPresentationTests {

    private func icon(_ kind: SystemHUD.Kind, _ value: Double, isMuted: Bool = false) -> String {
        HUDPresentation(hud: SystemHUD(kind: kind, value: value, isMuted: isMuted)).iconSystemName
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
