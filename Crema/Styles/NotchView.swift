import SwiftUI

/// Notch skin. Same discipline as CardView: shape/content derive
/// from `coordinator.state`, live scrubber position from `coordinator.nowPlaying`
/// (position never comes from the state payload), intents go
/// back as Coordinator method calls, no domain copies in @State. Hover detection
/// is not here: the panel's SurfaceHoverMonitor drives it against stable
/// regions, so the view never reacts to the animating frame.
///
/// The surface anchors at the slit but its content lives in the band below the
/// physical cutout (`notchSlitInset` reserves the dead-zone neck) — that's where
/// pixels are visible. The surface is sized per state (`surfaceStateSizes`) and
/// top-anchored inside the fixed window (sized to the largest state plus
/// overshoot headroom): all visible motion is SwiftUI's, under one morphing
/// outline, so no frame can ever show the material as a raw rectangle. Only the
/// inner content crossfades.
@MainActor
struct NotchView: View {
    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    /// Slit height for this display (injected by the panel). Content insets below
    /// it so nothing renders on the camera's dead-zone pixels.
    @Environment(\.notchSlitInset) private var slitInset
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Keyed on layoutKind, not the whole state, so HUD/scrubber value ticks
        // aren't animated (no slider rubber-banding); direction picks the spring.
        .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
        // Toggling view-only resizes the band while it is open — animate it too.
        .animation(SurfaceAnimation.open, value: showsControls)
    }

    private var surface: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: slitInset)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Uniform opaque black, no material and no stroke: the notch style
        // camouflages with the physical cutout (Dynamic Island), so any gray or
        // highlight would read as a seam against the hardware. The vibrancy
        // material is the floating skins' look — they float free and need no
        // camouflage.
        // The clip also bounds mid-morph content, which the fixed window
        // (larger than every state) never crops.
        .background(Color.black)
        .clipShape(shape)
        // Fixed black background ⇒ fixed dark palette, regardless of the
        // system appearance.
        .environment(\.colorScheme, .dark)
        .background(alignment: .top) {
            // Static full-slit underlay: the animated surface's rounded
            // outline (plus any nonzero NotchMetrics.lateralInset) doesn't
            // reach the cutout's rounded-corner live pixels, which would sit
            // bare. This rect covers them at the full slit width; its
            // geometry never changes during the morph, so its own edges never
            // re-rasterize — exactly the at-rest configuration that is clean.
            if let width = slitUnderlayWidth {
                Color.black.frame(width: width, height: slitInset)
            }
        }
        .opacity(layoutKind == .empty ? 0 : 1)
    }

    /// The inner content, crossfading between layouts (text/controls fade rather
    /// than jumping) while the surface outline morphs around it. The accent
    /// rides above the branches so its state survives compact↔expanded.
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

    /// The morphing outline: bottom corners flare more than the top, and the
    /// radii open up when expanded (design-reference §4.1).
    private var shape: NotchShape {
        switch layoutKind {
        case .expanded:
            NotchShape(topRadius: NotchMetrics.expandedTopRadius, bottomRadius: NotchMetrics.expandedBottomRadius)
        default:
            NotchShape(topRadius: NotchMetrics.compactTopRadius, bottomRadius: NotchMetrics.compactBottomRadius)
        }
    }

    /// Rule-derived size for the current layout; `.empty` keeps the compact size
    /// so appearing is a fade-in in place, not a grow-from-nothing.
    private var surfaceSize: CGSize? {
        guard let stateSizes else { return nil }
        switch layoutKind {
        case .empty, .compact: return stateSizes.compact
        case .expanded: return expandedSurfaceSize(stateSizes.expanded)
        case .hud: return stateSizes.hud
        }
    }

    /// View-only shrinks the expanded band by exactly the controls section, so
    /// the visible sections fill it with the same rhythm and no dead space; the
    /// fixed window is unchanged (it is always larger than any state).
    private func expandedSurfaceSize(_ full: CGSize) -> CGSize {
        guard !showsControls else { return full }
        return CGSize(width: full.width, height: full.height - NotchMetrics.controlsSectionHeight)
    }

    /// The underlay undoes the animated surface's lateral inset: rule width
    /// plus the inset back on each side = the slit's full bounding width.
    private var slitUnderlayWidth: CGFloat? {
        stateSizes.map { $0.compact.width + 2 * NotchMetrics.lateralInset }
    }

    /// The surface's layout identity, independent of the HUD/track value — so the
    /// morph animation fires on compact↔expanded↔hud transitions but not on the
    /// once-per-second position tick or a HUD level change.
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

    /// Controls are offered only while the write path works; otherwise the
    /// surface is read-only (no button that silently does nothing).
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
        HStack(spacing: 8) {
            ArtworkView(data: track.artworkData, side: 26, cornerRadius: 6)
            Text(track.title)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
            // Same live waveform as the other skins (one implementation):
            // dancing while playing, frozen when paused.
            WaveformGlyph(animating: track.isPlaying, config: NotchMetrics.waveform)
        }
        .padding(.horizontal, 12)
    }

    /// The reference layout on the narrow band: artwork + stacked text up top,
    /// thin scrubber, transport block at the base — the slit width has no room
    /// for a side-by-side control row. Fixed section heights sum to the
    /// derived expanded drop, so no dead space can pool between rows.
    private func expandedContent(_ track: NowPlaying) -> some View {
        VStack(spacing: NotchMetrics.expandedSectionGap) {
            HStack(spacing: NotchMetrics.expandedGap) {
                ArtworkView(
                    data: track.artworkData,
                    side: NotchMetrics.expandedArtworkSide,
                    cornerRadius: NotchMetrics.expandedArtworkRadius
                )
                TrackTextStack(title: track.title, artist: track.artist)
                Spacer(minLength: 0)
            }
            .frame(height: NotchMetrics.expandedArtworkSide)
            scrubber
                .frame(height: NotchMetrics.scrubberRowHeight)
            // View-only omits the transport row entirely; the band is sized
            // without it (expandedSurfaceSize), so the sections above fill it.
            if showsControls {
                TransportControls(
                    isPlaying: track.isPlaying,
                    enabled: controlsEnabled,
                    skipEnabled: skipControlsEnabled,
                    buttonSide: NotchMetrics.controlsHeight,
                    spacing: NotchMetrics.controlsSpacing,
                    onPrevious: { previousTapped() },
                    onPlayPause: { playPauseTapped() },
                    onNext: { nextTapped() }
                )
                .frame(maxWidth: .infinity)
                .frame(height: NotchMetrics.controlsHeight)
            }
        }
        .padding(.horizontal, NotchMetrics.expandedPaddingHorizontal)
        .padding(.vertical, NotchMetrics.expandedPaddingVertical)
    }

    private var scrubber: some View {
        ScrubberRow(
            position: scrubberPosition,
            duration: scrubberDuration,
            enabled: controlsEnabled,
            onScrub: { scrubbed(to: $0) }
        )
    }

    private func hudContent(_ hud: SystemHUD) -> some View {
        let presentation = HUDPresentation(hud: hud)
        // Same horizontal padding as compact: the two states share the exact
        // frame, so differing insets would jiggle edges during the crossfade.
        return HStack(spacing: 10) {
            Image(systemName: presentation.iconSystemName)
                .frame(width: 22)
            HUDLevelSlider(kind: hud.kind, value: presentation.value, onChange: { hudSliderMoved(to: $0) })
        }
        .padding(.horizontal, 12)
    }
}
