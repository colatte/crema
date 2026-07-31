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
        struct ProbeStyle: PresentationStyle {
            func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect {
                CGRect(x: geometry.frame.midX, y: CGFloat(geometry.safeTop), width: 10, height: 10)
            }

            func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> some View { EmptyView() }
        }

        let style = ProbeStyle()
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600), safeTop: 30)

        let first = style.frame(for: .hidden, on: geometry)
        let second = style.frame(for: .hidden, on: geometry)

        #expect(first == second)
        #expect(first.origin == CGPoint(x: 500, y: 30))
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
        _ = await eventually { h.coordinator.state == .nowPlaying(track, expanded: false) }

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
        var provenance = SurfaceProvenance()
        provenance.advance(to: .hud)
        #expect(provenance == SurfaceProvenance(previous: .hud, lastVisible: .hud))
        provenance.advance(to: .empty)
        #expect(provenance == SurfaceProvenance(previous: .empty, lastVisible: .hud))
    }

    @Test func advancingBetweenVisibleLayoutsMovesBoth() {
        var provenance = SurfaceProvenance()
        provenance.advance(to: .compact)
        provenance.advance(to: .expanded)
        #expect(provenance == SurfaceProvenance(previous: .expanded, lastVisible: .expanded))
    }
}
