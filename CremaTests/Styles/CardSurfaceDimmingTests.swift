import Testing
@testable import Crema

/// Which Card states show the glass bare and which dim it. The slider HUD is the
/// one that matches the system's OSD, pale over a pale page; everything carrying
/// white ink the contract holds to the minimum (the player's text, the filled
/// HUD's inverting glyph) is dimmed. Pinned on the effective layout, as the radius
/// is, so a surface fading out keeps its tone.
struct CardSurfaceDimmingTests {

    @Test func onlyTheSliderHUDShowsTheGlassBare() {
        #expect(!CardView.surfaceIsDimmed(for: .hud, indicator: .slider))
        #expect(CardView.surfaceIsDimmed(for: .hud, indicator: .filled))
    }

    @Test func everyPlayerStateIsDimmedWhateverTheIndicator() {
        for kind in [CardView.LayoutKind.compact, .expanded] {
            for indicator in HUDIndicatorStyle.allCases {
                #expect(CardView.surfaceIsDimmed(for: kind, indicator: indicator), "\(kind) with \(indicator)")
            }
        }
    }

    @Test func aHUDFadingOutKeepsTheToneItHad() {
        let kind = CardView.effectiveLayoutKind(layout: .empty, lastVisible: .hud)
        #expect(!CardView.surfaceIsDimmed(for: kind, indicator: .slider))
    }
}
