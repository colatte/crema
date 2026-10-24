import AppKit
import SwiftUI
import Testing
@testable import Crema

/// CardView: content is a function of coordinator state; intents go back
/// through Coordinator methods. Same contract as the other skins.
@MainActor
struct CardViewTests {

    @Test func contentIsAFunctionOfPresentationState() async {
        let h = CoordinatorHarness()
        let view = CardView(coordinator: h.coordinator)
        #expect(view.contentKind == .empty)

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { view.contentKind == .nowPlayingCompact(track) })

        h.coordinator.hover(true, on: .both)
        #expect(view.contentKind == .nowPlayingExpanded(track))

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)
        #expect(await eventually { view.contentKind == .hud(hud) })
    }

    @Test func adaptiveWidthKeyFollowsTheTrackNotTheTick() async {
        let h = CoordinatorHarness()
        let view = CardView(coordinator: h.coordinator)
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 10))
        #expect(await eventually { view.adaptiveWidthKey != nil })
        let key = view.adaptiveWidthKey

        // Position tick: the width driver must not move, or the card breathes
        // with playback — in compact and in expanded alike.
        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack(position: 11))
        #expect(await eventually { h.coordinator.nowPlaying?.position == 11 })
        #expect(view.adaptiveWidthKey == key)

        h.coordinator.hover(true, on: .both)
        #expect(view.adaptiveWidthKey == key)

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { view.contentKind == .hud(SystemHUD(kind: .volume, value: 0.5)) })
        #expect(view.adaptiveWidthKey == nil)   // HUD: fixed width, no key
    }

    @Test func compactAndExpandedSurfacesHugShortAndCapLongContent() async {
        // Rendered layout of the real surface (headless sizeThatFits) — with
        // only metrics pinned, the adaptive width can ship inert.
        let h = CoordinatorHarness()

        let short = NowPlaying(title: "Ay", isPlaying: true, position: 0)
        let long = NowPlaying(
            title: "The Continuing Story of Bungalow Bill (2018 Remaster)",
            artist: "The Beatles with a Very Long Credit Line",
            isPlaying: true,
            position: 0
        )

        h.nowPlayingSource.emit(short)
        #expect(await eventually { h.coordinator.state == .nowPlaying(short, expanded: false) })
        let compactProposal = CGSize(width: 364, height: CardMetrics.compact.height)
        let compactShort = NSHostingController(rootView: CardView(coordinator: h.coordinator).surface)
            .sizeThatFits(in: compactProposal)
        #expect(compactShort.width >= CardMetrics.compactMinWidth)
        #expect(compactShort.width < CardMetrics.compactMaxWidth)

        h.coordinator.hover(true, on: .both)
        #expect(await eventually { h.coordinator.state == .nowPlaying(short, expanded: true) })
        let expandedProposal = CGSize(width: 364, height: CardMetrics.expanded.height)
        let expandedShort = NSHostingController(rootView: CardView(coordinator: h.coordinator).surface)
            .sizeThatFits(in: expandedProposal)
        #expect(expandedShort.width >= CardMetrics.expandedMinWidth)
        #expect(expandedShort.width < CardMetrics.expandedMaxWidth)

        h.nowPlayingSource.emit(long)
        #expect(await eventually { h.coordinator.state == .nowPlaying(long, expanded: true) })
        let expandedCapped = NSHostingController(rootView: CardView(coordinator: h.coordinator).surface)
            .sizeThatFits(in: expandedProposal)
        // Truncation lands on a glyph boundary, so the hug settles at or just
        // under the ceiling — never past it.
        #expect(expandedCapped.width <= CardMetrics.expandedMaxWidth)
        #expect(expandedCapped.width > CardMetrics.expandedMaxWidth - 16)
    }

    @Test func intentsReachTheActuators() async {
        let h = CoordinatorHarness()
        let view = CardView(coordinator: h.coordinator)

        view.playPauseTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause] })

        view.previousTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack] })

        view.nextTapped()
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack, .nextTrack] })

        view.scrubbed(to: 42)
        #expect(await eventually { h.media.commands == [.togglePlayPause, .previousTrack, .nextTrack, .seek(seconds: 42)] })

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { view.contentKind == .hud(SystemHUD(kind: .volume, value: 0.5)) })
        view.hudSliderMoved(to: 0.7)
        #expect(await eventually { h.volume.commands == [.setVolume(0.7, display: nil)] })
    }

    @Test func aPanelDrawingOneLayerShowsThatLayerAlone() async {
        // The Card's HUD on a panel of its own: the HUD's panel never shows the
        // appearance, and the card's panel keeps it while the HUD is up.
        let h = CoordinatorHarness()
        let hudOnly = CardView(coordinator: h.coordinator, displayPolicy: SurfaceDisplayPolicy(surface: .hud))
        let cardOnly = CardView(coordinator: h.coordinator, displayPolicy: SurfaceDisplayPolicy(surface: .nowPlaying))

        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { cardOnly.contentKind == .nowPlayingCompact(track) })
        #expect(hudOnly.contentKind == .empty)

        let hud = SystemHUD(kind: .volume, value: 0.5)
        h.hudSource.emit(hud)
        #expect(await eventually { hudOnly.contentKind == .hud(hud) })
        #expect(cardOnly.contentKind == .nowPlayingCompact(track))
    }

    @Test func aPanelNotShowingTheHUDDrawsTheAppearanceUnderIt() async {
        // Another display's HUD: this panel draws both layers, shows none of the
        // HUD, and so shows what lies under it, as the card's own panel does
        // (docs/DECISIONS.md: hud-belongs-to-its-display).
        let h = CoordinatorHarness()
        let policy = SurfaceDisplayPolicy()
        let view = CardView(coordinator: h.coordinator, displayPolicy: policy)
        let track = CoordinatorHarness.playingTrack()
        h.nowPlayingSource.emit(track)
        #expect(await eventually { view.contentKind == .nowPlayingCompact(track) })

        policy.showsHUD = false
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.layers.hud != nil })

        #expect(view.contentKind == .nowPlayingCompact(track))
    }

    @Test func displayPolicySuppressesNowPlaying() async {
        let h = CoordinatorHarness()
        let policy = SurfaceDisplayPolicy()
        policy.showsNowPlaying = false
        let view = CardView(coordinator: h.coordinator, displayPolicy: policy)

        h.nowPlayingSource.emit(CoordinatorHarness.playingTrack())
        #expect(await eventually { h.coordinator.state != .hidden })

        #expect(view.contentKind == .empty)
    }
}
