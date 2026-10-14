import Testing
@testable import Crema

/// What each surface shows of the two layers: a surface drawing both shows the
/// HUD over the appearance, and a surface drawing one layer shows that layer
/// alone, whatever the other holds.
struct PresentationLayersTests {

    private let track = NowPlaying(title: "Breathe", artist: "Pink Floyd", isPlaying: true, position: 10, duration: 169)
    private let hud = SystemHUD(kind: .volume, value: 0.5)

    @Test func nothingOnEitherLayerShowsNothingAnywhere() {
        let layers = PresentationLayers()
        #expect(layers.state(on: .both) == .hidden)
        #expect(layers.state(on: .nowPlaying) == .hidden)
        #expect(layers.state(on: .hud) == .hidden)
    }

    @Test func theAppearanceAloneShowsWhereverItIsDrawn() {
        let layers = PresentationLayers(nowPlaying: .init(track: track, expanded: true))
        #expect(layers.state(on: .both) == .nowPlaying(track, expanded: true))
        #expect(layers.state(on: .nowPlaying) == .nowPlaying(track, expanded: true))
        #expect(layers.state(on: .hud) == .hidden)
    }

    @Test func theHUDCoversTheAppearanceOnlyWhereBothAreDrawn() {
        let layers = PresentationLayers(nowPlaying: .init(track: track, expanded: false), hud: hud)
        #expect(layers.state(on: .both) == .hud(hud))
        #expect(layers.state(on: .nowPlaying) == .nowPlaying(track, expanded: false))
        #expect(layers.state(on: .hud) == .hud(hud))
    }

    @Test func theHUDAloneLeavesTheAppearanceSurfaceEmpty() {
        let layers = PresentationLayers(hud: hud)
        #expect(layers.state(on: .both) == .hud(hud))
        #expect(layers.state(on: .nowPlaying) == .hidden)
        #expect(layers.state(on: .hud) == .hud(hud))
    }
}
