import Testing
@testable import Crema

/// The payloads here are verbatim captures from BetterDisplay 4.3.5 on a
/// built-in display, taken while it owned the brightness keys — not invented
/// shapes. If the app's format ever drifts, these are the tests that notice.
struct BetterDisplayOSDTranslationTests {

    private let builtIn = 1
    private let external = 99

    private func translate(_ json: String) -> SystemHUD? {
        BetterDisplayOSDTranslation.systemHUD(fromJSON: json) { [builtIn] id in id == builtIn }
    }

    @Test func aCapturedBrightnessPayloadBecomesAScreenBrightnessHUD() {
        let hud = translate(
            #"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"systemIconID":1,"value":40}"#
        )
        #expect(hud?.kind == .screenBrightness)
        #expect(hud?.value == 40.0 / 64.0)     // the scale is BetterDisplay's, not 0...1
        #expect(hud?.display == nil)           // nil is the domain's word for the built-in screen
    }

    @Test func everyBrightnessFlavourIsTheSameBarToTheUser() {
        for target in ["combinedBrightness", "hardwareBrightness", "softwareBrightness"] {
            let hud = translate(#"{"controlTarget":"\#(target)","maxValue":64,"value":32}"#)
            #expect(hud?.kind == .screenBrightness)
            #expect(hud?.value == 0.5)
        }
    }

    @Test func anotherDisplaysBrightnessIsNotDrawnAtAll() {
        // The screen-brightness actuator refuses every target but the built-in
        // one, so a HUD for an external display would arrive with a slider that
        // throws on the first drag. Crema draws a bar only where it can move it.
        #expect(translate(#"{"controlTarget":"combinedBrightness","displayID":99,"maxValue":64,"value":40}"#) == nil)
        #expect(external != builtIn)
    }

    @Test func volumeAndMuteAreLeftToCoreAudio() {
        // BetterDisplay reports them, but Core Audio already emits for every
        // volume change whoever caused it — translating these would draw twice.
        #expect(translate(#"{"controlTarget":"volume","systemIconID":3,"maxValue":100,"value":50}"#) == nil)
        #expect(translate(#"{"controlTarget":"mute","systemIconID":4,"maxValue":1,"value":0}"#) == nil)
    }

    @Test func controlsWithNoHUDOfOursStayInvisible() {
        // Contrast, gamma, temperature and friends ride the same notification.
        for target in ["contrast", "gamma", "temperature", "blueLight", "underscan"] {
            #expect(translate(#"{"controlTarget":"\#(target)","maxValue":64,"value":40}"#) == nil)
        }
    }

    @Test func withoutATargetTheIconDecides() {
        // Every field is optional in the published format.
        #expect(translate(#"{"systemIconID":1,"maxValue":64,"value":16}"#)?.value == 0.25)
        #expect(translate(#"{"systemIconID":3,"maxValue":64,"value":16}"#) == nil)
        #expect(translate(#"{"maxValue":64,"value":16}"#) == nil)
    }

    @Test func aPayloadNamingNoDisplayIsTakenAsTheBuiltInOne() {
        // Same default the domain itself uses when the field is absent.
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":64}"#)?.value == 1)
    }

    @Test func aBrokenPayloadIsIgnoredRatherThanGuessed() {
        #expect(translate("not json at all") == nil)
        #expect(translate("{}") == nil)
        #expect(translate(#"{"controlTarget":"combinedBrightness"}"#) == nil)          // no value
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":0,"value":40}"#) == nil)
    }

    @Test func aValueOutsideItsScaleIsClampedNotDrawnPastTheEnds() {
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":80}"#)?.value == 1)
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":-5}"#)?.value == 0)
    }
}
