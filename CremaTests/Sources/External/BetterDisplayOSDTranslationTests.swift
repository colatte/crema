import Testing
@testable import Crema

/// The payloads here are verbatim captures from BetterDisplay 4.3.5 on a
/// built-in display, taken while it owned the brightness keys — not invented
/// shapes. If the app's format ever drifts, these are the tests that notice.
struct BetterDisplayOSDTranslationTests {

    private let externalUUID = DisplayUUID(rawValue: "UUID-FOR-99")
    /// The built-in panel is named like any other display: the neighbour reports it
    /// by ID and the border resolves it to a UUID, so nothing here is nil except a
    /// payload that named no display at all.
    private let builtInUUID = DisplayUUID(rawValue: "UUID-FOR-1")

    private func translate(_ json: String) -> SystemHUD? {
        BetterDisplayOSDTranslation.systemHUD(fromJSON: json) { [externalUUID, builtInUUID] id in
            switch id {
            case 1: .display(builtInUUID)
            case 99: .display(externalUUID)
            default: nil          // a display the app cannot name
            }
        }
    }

    @Test func aCapturedBrightnessPayloadBecomesAScreenBrightnessHUD() {
        let hud = translate(
            #"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"systemIconID":1,"value":40}"#
        )
        #expect(hud?.kind == .screenBrightness)
        #expect(hud?.value == 40.0 / 64.0)     // the scale is BetterDisplay's, not 0...1
        // The built-in is NAMED here, not nil: the neighbour said which screen, and
        // nil is reserved for a payload that named none. Folding the two together
        // sent the bar to EVERY panel — measured in the field, pointer on the laptop.
        #expect(hud?.display == builtInUUID)
    }

    @Test func everyBrightnessFlavourIsTheSameBarToTheUser() {
        for target in ["combinedBrightness", "hardwareBrightness", "softwareBrightness"] {
            let hud = translate(#"{"controlTarget":"\#(target)","maxValue":64,"value":32}"#)
            #expect(hud?.kind == .screenBrightness)
            #expect(hud?.value == 0.5)
        }
    }

    @Test func anExternalDisplaysBrightnessCarriesThatDisplay() {
        // It names the screen it belongs to, which is what puts the bar on that
        // panel and sends the drag back to that display.
        let hud = translate(#"{"controlTarget":"combinedBrightness","displayID":99,"maxValue":64,"value":48}"#)
        #expect(hud?.display == externalUUID)
        #expect(hud?.value == 0.75)
        #expect(hud?.authority == .betterDisplay)
    }

    @Test func aDisplayTheAppCannotNameIsDropped() {
        // With no UUID there is no panel to place it on and no address to send a
        // drag back to — a bar Crema can neither show nor move.
        #expect(translate(#"{"controlTarget":"combinedBrightness","displayID":7,"maxValue":64,"value":48}"#) == nil)
    }

    @Test func aReportedLevelIsCreditedToTheAppThatReportedIt() {
        // The drag has to go back to the same scale the bar was drawn in.
        let hud = translate(#"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"value":48}"#)
        #expect(hud?.authority == .betterDisplay)
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

    @Test func aPayloadWithNoScaleIsDroppedRatherThanGivenOne() {
        // Guessing a maximum would draw a confidently wrong bar, and with the
        // neighbour's own OSD switched off that bar is the only feedback there is.
        #expect(translate(#"{"controlTarget":"combinedBrightness","value":40}"#) == nil)
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":-64,"value":40}"#) == nil)
    }

    @Test func aLockedControlIsNotDrawnAsAnOrdinaryBar() {
        // BetterDisplay marks controls the user cannot move; a bar that refuses
        // to budge reads as a broken HUD.
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":40,"lock":true}"#) == nil)
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":40,"lock":false}"#) != nil)
    }

    @Test func aValueOutsideItsScaleIsClampedNotDrawnPastTheEnds() {
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":80}"#)?.value == 1)
        #expect(translate(#"{"controlTarget":"combinedBrightness","maxValue":64,"value":-5}"#)?.value == 0)
    }
}
