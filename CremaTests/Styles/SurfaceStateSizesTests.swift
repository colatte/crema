import CoreGraphics
import Testing
@testable import Crema

/// The per-state sizes the panel injects must be exactly the frame rule's — the
/// rule stays the one source of truth for dimensions, and the view's sized
/// surface lands on the same rect the window will snap to.
struct SurfaceStateSizesTests {

    private let track = NowPlaying(title: "Breathe", artist: "Pink Floyd", isPlaying: true, position: 10, duration: 169)
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))

    @Test func notchSizesComeFromItsFrameRule() {
        let style = NotchStyle()
        let sizes = style.stateSizes(on: notched)
        #expect(sizes.compact == style.frame(for: .nowPlaying(track, expanded: false), on: notched).size)
        #expect(sizes.expanded == style.frame(for: .nowPlaying(track, expanded: true), on: notched).size)
        #expect(sizes.hud == style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: notched).size)
    }

    @Test func cardSizesComeFromItsFrameRule() {
        let style = CardStyle()
        let sizes = style.stateSizes(on: plain)
        #expect(sizes.compact == CardMetrics.compact)
        #expect(sizes.expanded == CardMetrics.expanded)
        #expect(sizes.hud == CardMetrics.hud)
    }

    @Test func hudPayloadNeverAffectsTheSize() {
        // Guards the reference-payload trick: rules size by state case only.
        let style = CardStyle()
        let volume = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.1)), on: plain).size
        let brightness = style.frame(for: .hud(SystemHUD(kind: .screenBrightness, value: 0.9)), on: plain).size
        #expect(volume == brightness)
        #expect(style.stateSizes(on: plain).hud == volume)
    }

    @Test func styleDispatchCoversEverySkin() {
        #expect(Style.notch.stateSizes(on: notched) == NotchStyle().stateSizes(on: notched))
        #expect(Style.card.stateSizes(on: plain) == CardStyle().stateSizes(on: plain))
        #expect(Style.classic.stateSizes(on: plain) == ClassicStyle().stateSizes(on: plain))
    }
}
