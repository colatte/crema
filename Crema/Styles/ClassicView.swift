import SwiftUI

/// Classic skin view. Same discipline as CardView: shape/content derive from
/// `coordinator.state` (through the display policy), live scrubber position
/// from `coordinator.nowPlaying`, intents go back as Coordinator method calls,
/// no domain copies in @State. The surface is sized per state and
/// bottom-anchored inside the fixed window — the block sits on the native
/// OSD's line and grows upward.
@MainActor
struct ClassicView: View {
    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    @Environment(\.surfaceStateSizes) private var stateSizes
    @Environment(\.surfaceSizeReporter) private var reportSurfaceSize

    var body: some View {
        Group {
            if let size = surfaceSize {
                surface.frame(width: size.width, height: size.height)
            } else {
                surface
            }
        }
        // The rendered size is the click-interactive truth: view-only shortens
        // the surface, so the panel must follow what is actually drawn.
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { size in
            reportSurfaceSize?(size)
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Keyed on layoutKind so value ticks don't animate; direction picks the
        // spring.
        .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
        // Toggling view-only resizes the block while it is open — animate it too.
        .animation(SurfaceAnimation.open, value: showsControls)
    }

    private var surface: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .vibrantSurface(in: RoundedRectangle(cornerRadius: ClassicMetrics.cornerRadius, style: .continuous))
            .opacity(layoutKind == .empty ? 0 : 1)
    }

    /// The accent rides above the branches so its state survives
    /// compact↔expanded.
    @ViewBuilder private var content: some View {
        ZStack {
            switch contentKind {
            case .empty:
                Color.clear
            case .nowPlayingCompact(let track):
                compactContent(track).transition(.opacity)
            case .nowPlayingExpanded(let track):
                expandedContent(track).transition(.opacity)
            case .hud(let hud):
                hudContent(hud).transition(.opacity)
            }
        }
        .artworkAccent(from: accentArtwork)
    }

    private var surfaceSize: CGSize? {
        guard let stateSizes else { return nil }
        switch layoutKind {
        case .empty, .compact: return stateSizes.compact
        case .expanded: return expandedSurfaceSize(stateSizes.expanded)
        case .hud: return stateSizes.hud
        }
    }

    /// View-only shrinks the expanded block by exactly the controls section, so
    /// the visible sections fill it with no dead space; the fixed window is
    /// unchanged (always larger than any state).
    private func expandedSurfaceSize(_ full: CGSize) -> CGSize {
        guard !showsControls else { return full }
        return CGSize(width: full.width, height: full.height - ClassicMetrics.controlsSectionHeight)
    }

    private enum LayoutKind: Equatable {
        case empty, compact, expanded, hud
    }

    private var layoutKind: LayoutKind {
        switch contentKind {
        case .empty: .empty
        case .nowPlayingCompact: .compact
        case .nowPlayingExpanded: .expanded
        case .hud: .hud
        }
    }

    private var isExpanded: Bool {
        if case .nowPlaying(_, expanded: true) = coordinator.state { return true }
        return false
    }


    /// Artwork bytes driving the accent — from the state payload (ticks never
    /// rewrite it); nil outside now-playing, so the tone fades out with the
    /// surface.
    private var accentArtwork: [UInt8]? {
        switch contentKind {
        case .nowPlayingCompact(let track), .nowPlayingExpanded(let track):
            track.artworkData
        case .empty, .hud:
            nil
        }
    }

    // MARK: - Content derivation (state in)

    var contentKind: StyleContent {
        StyleContent(state: coordinator.state, showsNowPlaying: displayPolicy.showsNowPlaying)
    }

    /// Live scrubber position — read from `nowPlaying`, never from `state`.
    var scrubberPosition: Double {
        coordinator.nowPlaying?.position ?? 0
    }

    var scrubberDuration: Double? {
        coordinator.nowPlaying?.duration
    }

    var controlsEnabled: Bool {
        coordinator.commandsAvailable
    }

    var skipControlsEnabled: Bool {
        coordinator.skipControlsEnabled
    }

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

    // MARK: - Rendering

    private func compactContent(_ track: NowPlaying) -> some View {
        VStack(spacing: 8) {
            ArtworkView(
                data: track.artworkData,
                side: ClassicMetrics.compactArtworkSide,
                cornerRadius: ClassicMetrics.compactArtworkRadius
            )
            TrackTextStack(title: track.title, artist: track.artist, alignment: .center)
            WaveformGlyph(animating: track.isPlaying, config: ClassicMetrics.waveform)
        }
        .padding(ClassicMetrics.contentPadding)
    }

    /// The reference layout in the centered block: artwork on top (the
    /// anchor), stacked text, thin scrubber, transport at the base — the same
    /// family pattern, gravity-centered like the native OSD it modernizes.
    /// Fixed section heights sum to the derived expanded size.
    private func expandedContent(_ track: NowPlaying) -> some View {
        VStack(spacing: ClassicMetrics.contentGap) {
            ArtworkView(
                data: track.artworkData,
                side: ClassicMetrics.expandedArtworkSide,
                cornerRadius: ClassicMetrics.expandedArtworkRadius
            )
            TrackTextStack(title: track.title, artist: track.artist, alignment: .center)
                .frame(height: ClassicMetrics.textStackHeight)
            scrubber
                .frame(height: ClassicMetrics.scrubberRowHeight)
            // View-only omits the transport row; the block is sized without it
            // (expandedSurfaceSize), so the sections above fill it.
            if showsControls {
                TransportControls(
                    isPlaying: track.isPlaying,
                    enabled: controlsEnabled,
                    skipEnabled: skipControlsEnabled,
                    buttonSide: ClassicMetrics.controlsHeight,
                    onPrevious: { previousTapped() },
                    onPlayPause: { playPauseTapped() },
                    onNext: { nextTapped() }
                )
                .frame(height: ClassicMetrics.controlsHeight)
            }
        }
        .padding(ClassicMetrics.contentPadding)
    }

    private var scrubber: some View {
        ScrubberRow(
            position: scrubberPosition,
            duration: scrubberDuration,
            enabled: controlsEnabled,
            onScrub: { scrubbed(to: $0) }
        )
    }

    /// The native OSD's layout: a big centered icon over the level control.
    private func hudContent(_ hud: SystemHUD) -> some View {
        let presentation = HUDPresentation(hud: hud)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Image(systemName: presentation.iconSystemName)
                .font(.system(size: ClassicMetrics.hudIconSize))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Slider(
                value: Binding(
                    get: { presentation.value },
                    set: { hudSliderMoved(to: $0) }
                )
            )
        }
        .padding(ClassicMetrics.contentPadding + 8)
    }
}
