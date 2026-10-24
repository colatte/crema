import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// Style contract, ScreenGeometry and the skin skeleton's provenance: pure
/// values and a pure frame rule, no view and no environment.
@MainActor
struct StyleContractTests {

    @Test func screenGeometryDefaultsToNoNotch() {
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(geometry.safeTop == 0)
        #expect(geometry.auxLeft == 0)
        #expect(geometry.auxRight == 0)
    }

    @Test func screenGeometryIsSendable() {
        // The real check is the compile-time requireSendable constraint below:
        // ScreenGeometry must stay Sendable. Losing it fails the build, not this
        // assertion — the #expect is a vestigial runtime line.
        func requireSendable<T: Sendable>(_: T.Type) {}
        requireSendable(ScreenGeometry.self)
        #expect(Bool(true))
    }

    @Test func frameRuleIsAPureFunctionOfStateAndGeometry() {
        // Every shipped skin, every state: the same inputs, asked again, give the
        // same rect. A rule that kept anything between calls (a cache keyed wrong,
        // a counter, a clock) would answer the second asking differently.
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let notched = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32, auxLeft: 663.5, auxRight: 663.5
        )
        let track = CoordinatorHarness.playingTrack()
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        for style in Style.allCases {
            let geometry = style == .notch ? notched : plain
            for state in states {
                let first = style.frame(for: state, on: geometry)
                let second = style.frame(for: state, on: geometry)
                #expect(first == second, "\(style) \(state)")
            }
        }
    }

    @Test func styleContentIsAPureMappingOfState() {
        let track = CoordinatorHarness.playingTrack()
        let hud = SystemHUD(kind: .volume, value: 0.5)

        #expect(StyleContent(state: .hidden) == .empty)
        #expect(StyleContent(state: .nowPlaying(track, expanded: false)) == .nowPlayingCompact(track))
        #expect(StyleContent(state: .nowPlaying(track, expanded: true)) == .nowPlayingExpanded(track))
        #expect(StyleContent(state: .hud(hud)) == .hud(hud))
    }

    @Test func displayPolicySuppressesOnlyNowPlaying() {
        // The fixed window never orders out, so "show now playing here" off
        // must suppress at the content level — HUDs still render.
        let track = CoordinatorHarness.playingTrack()
        let hud = SystemHUD(kind: .volume, value: 0.5)

        #expect(StyleContent(state: .nowPlaying(track, expanded: false), showsNowPlaying: false) == .empty)
        #expect(StyleContent(state: .nowPlaying(track, expanded: true), showsNowPlaying: false) == .empty)
        #expect(StyleContent(state: .hud(hud), showsNowPlaying: false) == .hud(hud))
        #expect(StyleContent(state: .hidden, showsNowPlaying: false) == .empty)
    }

    @Test func viewsDeriveContentThroughTheDisplayPolicy() async {
        let h = CoordinatorHarness()
        let policy = SurfaceDisplayPolicy()
        policy.showsNowPlaying = false
        let card = CardView(coordinator: h.coordinator, displayPolicy: policy)
        let notch = NotchView(coordinator: h.coordinator, displayPolicy: policy)

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) })

        #expect(card.contentKind == .empty)
        #expect(notch.contentKind == .empty)

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)
        #expect(await eventually { card.contentKind == .hud(hud) })
        #expect(notch.contentKind == .hud(hud))
    }

    // MARK: - Surface provenance (one advance rule for all three skins)

    @Test func provenanceStartsAtTheEmptyBoundaryAndFreezesOnCompact() {
        // Nothing shown yet reads as an appearance (previous == .empty, so the
        // first visible layout is gated as the boundary crossing it is), and the
        // freeze falls back to the compact silhouette.
        let provenance = SurfaceProvenance()
        #expect(provenance.previous == .empty)
        #expect(provenance.lastVisible == .compact)
    }

    @Test func advancingToHiddenKeepsTheLastVisibleLayout() {
        // The two fields answer different questions, which is why they are two:
        // `previous` follows every kind (a disappearance must not be gated as a
        // morph), while `lastVisible` skips `.empty` so the fade-out sits on the
        // rect it is leaving instead of snapping to compact behind the fade.
        let hud = StyleContent.hud(SystemHUD(kind: .volume, value: 0.5))
        var provenance = SurfaceProvenance()
        provenance.advance(to: hud)
        #expect(provenance == SurfaceProvenance(previous: .hud, lastVisible: .hud, lastVisibleContent: hud))
        provenance.advance(to: .empty)
        #expect(provenance == SurfaceProvenance(previous: .empty, lastVisible: .hud, lastVisibleContent: hud))
    }

    @Test func advancingBetweenVisibleLayoutsMovesBoth() {
        let track = NowPlaying(title: "Breathe", artist: "Pink Floyd", isPlaying: true, position: 10, duration: 169)
        var provenance = SurfaceProvenance()
        provenance.advance(to: .nowPlayingCompact(track))
        provenance.advance(to: .nowPlayingExpanded(track))
        #expect(provenance == SurfaceProvenance(
            previous: .expanded, lastVisible: .expanded, lastVisibleContent: .nowPlayingExpanded(track)
        ))
    }

    @Test func aHiddenSurfaceDrawsWhatItLastShowed() {
        // Hidden and shown are two states of one surface: removed as a branch, the
        // content took a fade of its own under the surface's, and went out at the
        // square of its opacity, ahead of its outline.
        let hud = StyleContent.hud(SystemHUD(kind: .screenBrightness, value: 0.7))
        #expect(SurfaceLayout.drawnContent(.empty, lastVisible: hud) == hud)
        let other = StyleContent.hud(SystemHUD(kind: .volume, value: 0.2))
        #expect(SurfaceLayout.drawnContent(other, lastVisible: hud) == other)
        // Before anything has shown there is nothing to keep.
        #expect(SurfaceLayout.drawnContent(.empty, lastVisible: .empty) == .empty)
    }
}
