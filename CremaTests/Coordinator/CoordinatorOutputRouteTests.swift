import Testing
@testable import Crema

/// The output route rides the volume reading from the source to the state the
/// skins draw, with nothing in between deciding on it.
@MainActor
struct CoordinatorOutputRouteTests {

    @Test func aReadingCarriesItsRouteToTheState() async {
        let h = CoordinatorHarness()
        let hud = SystemHUD(kind: .volume, value: 0.6, route: .airPodsPro)

        h.hudSource.emit(hud)

        #expect(await eventually { h.coordinator.state == .hud(hud) })
        guard case .hud(let shown) = h.coordinator.state else { return }
        #expect(HUDPresentation(hud: shown).iconSystemName == "airpodspro")
    }

    @Test func theNextReadingAfterADeviceSwitchDrawsTheNewGlyph() async {
        let h = CoordinatorHarness()
        let speakers = SystemHUD(kind: .volume, value: 0.6, route: .builtInSpeakers)
        h.hudSource.emit(speakers)
        #expect(await eventually { h.coordinator.state == .hud(speakers) })

        let headphones = SystemHUD(kind: .volume, value: 0.6, route: .wiredHeadphones)
        h.hudSource.emit(headphones)

        #expect(await eventually { h.coordinator.state == .hud(headphones) })
        guard case .hud(let shown) = h.coordinator.state else { return }
        #expect(HUDPresentation(hud: shown).iconSystemName == "headphones")
    }
}
