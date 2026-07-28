import SwiftUI

/// The surface's layout identity, independent of the HUD/track value — shared
/// by every skin (each aliases it as `LayoutKind`), so the morph animation
/// fires on compact↔expanded↔hud transitions but never on the once-per-second
/// position tick or a HUD level change.
enum SurfaceLayoutKind: Equatable {
    case empty, compact, expanded, hud
}

/// The pure layout rules every skin shares — one implementation, so a contract
/// fix cannot land on two skins and miss the third (the empty-boundary freeze
/// did exactly that before it was pinned). Each view keeps a one-line static
/// delegating here; the per-skin parameter is only which Metrics constant
/// feeds `controlsSectionHeight`.
enum SurfaceLayout {
    /// The layout whose geometry the surface presents: visible layouts are
    /// themselves; a hidden surface FREEZES the last-visible layout so every
    /// fade-out sits on the rect it is leaving (no snap to a compact
    /// silhouette behind a fading HUD, no mirror shrink on dismissal).
    /// Initial (nothing shown yet) falls back to compact.
    nonisolated static func effectiveLayoutKind(
        layout: SurfaceLayoutKind,
        lastVisible: SurfaceLayoutKind
    ) -> SurfaceLayoutKind {
        layout == .empty ? lastVisible : layout
    }

    nonisolated static func surfaceSize(
        for kind: SurfaceLayoutKind,
        in stateSizes: SurfaceStateSizes,
        showsControls: Bool,
        controlsSectionHeight: CGFloat
    ) -> CGSize {
        switch kind {
        case .empty, .compact: stateSizes.compact
        case .expanded: expandedSurfaceSize(
                stateSizes.expanded, showsControls: showsControls, controlsSectionHeight: controlsSectionHeight
            )
        case .hud: stateSizes.hud
        }
    }

    /// View-only shrinks the expanded surface by exactly the controls section,
    /// so the visible sections fill it with no dead space; the fixed window is
    /// unchanged (always larger than any state).
    nonisolated static func expandedSurfaceSize(
        _ full: CGSize,
        showsControls: Bool,
        controlsSectionHeight: CGFloat
    ) -> CGSize {
        guard !showsControls else { return full }
        return CGSize(width: full.width, height: full.height - controlsSectionHeight)
    }
}

/// The non-visual skeleton every skin shares: state in (content/layout
/// derivation off the Coordinator, through the display policy) and intent out
/// (Coordinator method passthroughs — what the unit tests invoke directly).
/// A skin conforms and keeps only its visual body plus the provenance @State
/// the freeze contract needs — which cannot live here, and is what the
/// per-view `effectiveLayoutKind` accessors bind to.
@MainActor
protocol SurfaceStyleBody {
    var coordinator: Coordinator { get }
    var displayPolicy: SurfaceDisplayPolicy { get }
}

extension SurfaceStyleBody {

    // MARK: - Content derivation (state in)

    var contentKind: StyleContent {
        StyleContent(state: coordinator.state, showsNowPlaying: displayPolicy.showsNowPlaying)
    }

    var layoutKind: SurfaceLayoutKind {
        switch contentKind {
        case .empty: .empty
        case .nowPlayingCompact: .compact
        case .nowPlayingExpanded: .expanded
        case .hud: .hud
        }
    }

    var isExpanded: Bool {
        if case .nowPlaying(_, expanded: true) = coordinator.state { return true }
        return false
    }

    /// Artwork bytes driving the accent — from the state payload (ticks never
    /// rewrite it); nil outside now-playing, so the tone fades out with the
    /// surface.
    var accentArtwork: [UInt8]? {
        switch contentKind {
        case .nowPlayingCompact(let track), .nowPlayingExpanded(let track):
            track.artworkData
        case .empty, .hud:
            nil
        }
    }

    /// Live scrubber position — read from `nowPlaying`, never from `state`.
    var scrubberPosition: Double {
        coordinator.nowPlaying?.position ?? 0
    }

    var scrubberDuration: Double? {
        coordinator.nowPlaying?.duration
    }

    /// Controls are offered only while the write path works; otherwise the
    /// surface is read-only (no button that silently does nothing).
    var controlsEnabled: Bool {
        coordinator.commandsAvailable
    }

    var skipControlsEnabled: Bool {
        coordinator.skipControlsEnabled
    }

    /// View-only mode (Settings): the expanded surface drops the transport row
    /// and shrinks by exactly that section (expandedSurfaceSize), so the
    /// visible sections fill it with no pooled gap.
    var showsControls: Bool {
        displayPolicy.showsControls
    }

    // MARK: - Intents (methods out) — unit tests invoke these directly.

    func playPauseTapped() {
        coordinator.togglePlayPause()
    }

    func previousTapped() {
        coordinator.previousTrack()
    }

    func nextTapped() {
        coordinator.nextTrack()
    }

    func scrubbed(to seconds: Double) {
        coordinator.scrub(to: seconds)
    }

    func hudSliderMoved(to value: Double) {
        coordinator.hudSliderChanged(to: value)
    }
}
