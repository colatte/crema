import SwiftUI

/// Classic skin view. Same discipline as CardView: shape/content derive from
/// `coordinator.state` (through the display policy), live scrubber position
/// from `coordinator.nowPlaying`, intents go back as Coordinator method calls,
/// no domain copies in @State. The surface is sized per state and
/// bottom-anchored inside the fixed window — the block sits on the native
/// OSD's line and grows upward.
@MainActor
struct ClassicView: View, SurfaceStyleBody {
    /// The shared surface vocabulary (SurfaceStyleCore); aliased so call sites
    /// and tests keep the per-skin spelling.
    typealias LayoutKind = SurfaceLayoutKind

    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    @Environment(\.surfaceStateSizes) private var stateSizes
    @Environment(\.surfaceSizeReporter) private var reportSurfaceSize

    /// Gates every surface morph to a dry landing (MG5) — see
    /// `SurfaceAnimation.geometryAnimation`; the opacity fade stays regardless.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The layout the surface is coming FROM, for provenance-aware geometry
    /// (see `geometryAnimation`). Ephemeral, purely visual. Advanced in
    /// `onChange` AFTER the render that reads it (evaluation-order subtlety in
    /// the body comment).
    @State private var previousLayoutKind: LayoutKind = .empty

    /// The last VISIBLE layout — advanced only on non-empty kinds, so it survives
    /// the whole hidden period. The hidden surface freezes its geometry to this
    /// (`effectiveLayoutKind`), so a fade-out sits on the rect it is leaving
    /// instead of snapping to the compact block behind a fading HUD.
    @State private var lastVisibleLayoutKind: LayoutKind = .compact

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
        // The block morphs only between visible layouts; an appearance from or
        // disappearance to `.empty` snaps its frame so the HUD (200²) born from
        // hidden lands there instead of growing up from the compact 170² rect
        // (the fade lives on the opacity, animated separately in `surface`).
        // geometryAnimation reads `previousLayoutKind`, which still holds the OLD
        // kind during the body pass that first sees the NEW layoutKind — the
        // onChange below advances it afterward, so this pass gets true provenance.
        .animation(geometryAnimation, value: layoutKind)
        // Toggling view-only resizes the block while it is open — animate it too,
        // dry under Reduce Motion like the geometry spring.
        .animation(SurfaceAnimation.morph(reduceMotion: reduceMotion), value: showsControls)
        .onChange(of: layoutKind) { _, newValue in
            previousLayoutKind = newValue
            // Skip `.empty`: the frozen-geometry contract needs the last VISIBLE
            // layout to persist across the whole hidden period.
            if newValue != .empty { lastVisibleLayoutKind = newValue }
        }
    }

    /// Snap on an appearance/disappearance (either side `.empty`), morph between
    /// visible layouts. The block's corner radius is constant, so only the frame
    /// carries geometry here.
    private var geometryAnimation: Animation? {
        SurfaceAnimation.geometryAnimation(
            fromEmpty: previousLayoutKind == .empty,
            toEmpty: layoutKind == .empty,
            expanding: isExpanded,
            reduceMotion: reduceMotion
        )
    }

    /// Content-crossfade provenance (see `SurfaceAnimation.contentAnimation`):
    /// nil on an appearance so the content — and the material sized off it —
    /// snaps to the destination rather than springing past the snapped outer
    /// frame; the directional spring otherwise, so the outgoing content fades.
    private var contentAnimation: Animation? {
        SurfaceAnimation.contentAnimation(
            fromEmpty: previousLayoutKind == .empty,
            expanding: isExpanded,
            reduceMotion: reduceMotion
        )
    }

    private var surface: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Closest scope to the branches, and it governs the bounds the
            // material/clip/stroke are sized off (vibrantSurface's
            // `.background`/clip size to the node below them). Provenance-aware:
            // nil on an appearance snaps that geometry to the destination (no
            // material springing past the snapped outer frame — the ghost behind
            // the HUD), the directional spring on a disappearance fades the
            // content out, and between visible layouts it is the crossfade+morph.
            .animation(contentAnimation, value: layoutKind)
            .vibrantSurface(in: RoundedRectangle(cornerRadius: ClassicMetrics.cornerRadius, style: .continuous))
            .opacity(layoutKind == .empty ? 0 : 1)
            // The appearance/disappearance fade: opacity keeps its spring even
            // when the geometry snaps, so a block born from hidden fades in at
            // its final rect. Only fires on empty↔visible — opacity is 1 across
            // every visible transition — so its choice never touches a
            // visible→visible morph.
            .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
            // Pinned dark ENCLOSING vibrantSurface — same contract and same
            // placement rationale as CardView (docs/DECISIONS.md:
            // hud-fixed-dark-palette).
            .environment(\.colorScheme, .dark)
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
        return Self.surfaceSize(for: effectiveLayoutKind, in: stateSizes, showsControls: showsControls)
    }

    // One-line delegates into SurfaceLayout (the shared implementation): the
    // per-skin fact is only which Metrics feeds controlsSectionHeight, and the
    // per-view spelling is what SurfaceEmptyGeometryTests pins.
    nonisolated static func surfaceSize(
        for kind: LayoutKind,
        in stateSizes: SurfaceStateSizes,
        showsControls: Bool
    ) -> CGSize {
        SurfaceLayout.surfaceSize(
            for: kind, in: stateSizes, showsControls: showsControls,
            controlsSectionHeight: ClassicMetrics.controlsSectionHeight
        )
    }

    nonisolated static func effectiveLayoutKind(layout: LayoutKind, lastVisible: LayoutKind) -> LayoutKind {
        SurfaceLayout.effectiveLayoutKind(layout: layout, lastVisible: lastVisible)
    }

    /// Binds the shared freeze rule to this view's provenance @State
    /// (see SurfaceLayout.effectiveLayoutKind for the contract).
    private var effectiveLayoutKind: LayoutKind {
        Self.effectiveLayoutKind(layout: layoutKind, lastVisible: lastVisibleLayoutKind)
    }

    // MARK: - Rendering

    private func compactContent(_ track: NowPlaying) -> some View {
        VStack(spacing: ClassicMetrics.compactGap) {
            ArtworkView(
                data: track.artworkData,
                side: ClassicMetrics.compactArtworkSide,
                cornerRadius: ClassicMetrics.compactArtworkRadius
            )
            TrackTextStack(title: track.title, artist: track.artist, alignment: .center)
            // Compact only: here it is the sole "playing" signal. Expanded
            // already says it twice (scrubber motion + pause glyph).
            WaveformGlyph(animating: track.isPlaying)
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
                // Softer than the siblings' primary tint on purpose: the whole
                // skin echoes the translucent pre-Tahoe bezel, so the glyph
                // carries the same lowered contrast as the segmented track.
                .foregroundStyle(.secondary)
                .symbolReplace(on: presentation.iconSystemName)
            Spacer(minLength: 0)
            HUDLevelSlider(kind: hud.kind, value: presentation.value, onChange: { hudSliderMoved(to: $0) }, appearance: .segmented)
        }
        .padding(ClassicMetrics.hudPadding)
    }
}
