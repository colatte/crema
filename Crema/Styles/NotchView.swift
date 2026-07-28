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
struct NotchView: View, SurfaceStyleBody {
    /// The shared surface vocabulary (SurfaceStyleCore); aliased so call sites
    /// and tests keep the per-skin spelling.
    typealias LayoutKind = SurfaceLayoutKind

    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    /// Slit height for this display (injected by the panel). Content insets below
    /// it so nothing renders on the camera's dead-zone pixels.
    @Environment(\.notchSlitInset) private var slitInset
    @Environment(\.surfaceStateSizes) private var stateSizes
    @Environment(\.surfaceSizeReporter) private var reportSurfaceSize

    /// Gates every surface morph to a dry landing (MG5) — see
    /// `SurfaceAnimation.geometryAnimation`; the opacity fade stays regardless.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The layout the surface is coming FROM, for provenance-aware geometry
    /// (see `geometryAnimation`). Ephemeral, purely visual. Advanced in
    /// `onChange` AFTER the render that reads it (evaluation-order subtlety in
    /// the body comment) — the same mechanism as Card/Classic.
    @State private var previousLayoutKind: LayoutKind = .empty

    /// The last VISIBLE layout — advanced only on non-empty kinds, so it survives
    /// the whole hidden period. The hidden surface freezes its geometry AND its
    /// shape flare to this (`effectiveLayoutKind`), so a fade-out sits on the drop
    /// (and radii) it is leaving instead of telescoping to compact behind the fade.
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Geometry: the frame morphs only between visible layouts; an appearance
        // from or disappearance to `.empty` snaps it (geometryAnimation → nil), so
        // the black surface lands at its final drop instead of telescoping the
        // expanded↔compact height across the fade (the fade lives on the opacity,
        // the flare on its own snap — both in `surface`). geometryAnimation reads
        // `previousLayoutKind`, which still holds the OLD kind during the body pass
        // that first sees the NEW layoutKind; the onChange advances it afterward,
        // so this pass gets true provenance. Keyed on layoutKind, not the whole
        // state, so HUD/scrubber value ticks aren't animated.
        .animation(geometryAnimation, value: layoutKind)
        // Toggling view-only resizes the band while it is open — a visible morph,
        // so it honors Reduce Motion (nil) like the geometry spring.
        .animation(SurfaceAnimation.morph(reduceMotion: reduceMotion), value: showsControls)
        .onChange(of: layoutKind) { _, newValue in
            previousLayoutKind = newValue
            // Skip `.empty`: the frozen-geometry contract needs the last VISIBLE
            // layout to persist across the whole hidden period.
            if newValue != .empty { lastVisibleLayoutKind = newValue }
        }
    }

    /// Snap on an appearance/disappearance (either side `.empty`), morph between
    /// visible layouts; nil under Reduce Motion. Provenance comes from
    /// `previousLayoutKind` (the FROM) and `layoutKind` (the TO); scoped to the
    /// frame and the shape flare only, so the opacity fade is untouched.
    private var geometryAnimation: Animation? {
        SurfaceAnimation.geometryAnimation(
            fromEmpty: previousLayoutKind == .empty,
            toEmpty: layoutKind == .empty,
            expanding: isExpanded,
            reduceMotion: reduceMotion
        )
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
        // The flare is geometry too: the expanded outline opens into wider radii,
        // so it morphs compact/HUD↔expanded but SNAPS across the empty boundary and
        // holds the last-visible flare while hidden — same provenance gate as the
        // frame. Keyed on the expanded-ness so it fires only when the flare
        // actually changes (never on the compact↔HUD same-shape transition).
        .animation(geometryAnimation, value: shapeIsExpanded)
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
        // The appearance/disappearance fade: opacity keeps its spring even when the
        // geometry and flare snap, so a surface born from hidden fades in at its
        // final drop. A fade is Reduce-Motion-safe, so it is NOT gated. Only fires
        // on empty↔visible (opacity is 1 across every visible transition), so its
        // choice never touches a visible→visible morph.
        .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
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
    /// radii open up when expanded (design-reference §4.1). Keyed on the EFFECTIVE
    /// layout so a hidden surface keeps the flare it faded out with.
    private var shape: NotchShape { Self.shape(for: effectiveLayoutKind) }

    /// Whether the current flare is the expanded one — the animation key, so the
    /// shape spring fires only when the outline actually changes.
    private var shapeIsExpanded: Bool { effectiveLayoutKind == .expanded }

    nonisolated static func shape(for kind: LayoutKind) -> NotchShape {
        switch kind {
        case .expanded:
            NotchShape(topRadius: NotchMetrics.expandedTopRadius, bottomRadius: NotchMetrics.expandedBottomRadius)
        default:
            NotchShape(topRadius: NotchMetrics.compactTopRadius, bottomRadius: NotchMetrics.compactBottomRadius)
        }
    }

    /// Rule-derived size for the EFFECTIVE layout; a hidden surface freezes the
    /// last-visible rect (`effectiveLayoutKind`) so appearing/disappearing is a
    /// fade in place, never a telescope across the expanded↔compact drop.
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
            controlsSectionHeight: NotchMetrics.controlsSectionHeight
        )
    }

    /// The underlay undoes the animated surface's lateral inset: rule width
    /// plus the inset back on each side = the slit's full bounding width.
    private var slitUnderlayWidth: CGFloat? {
        stateSizes.map { $0.compact.width + 2 * NotchMetrics.lateralInset }
    }

    nonisolated static func effectiveLayoutKind(layout: LayoutKind, lastVisible: LayoutKind) -> LayoutKind {
        SurfaceLayout.effectiveLayoutKind(layout: layout, lastVisible: lastVisible)
    }

    /// Binds the shared freeze rule to this view's provenance @State — here it
    /// freezes the drop AND the shape flare (see SurfaceLayout.effectiveLayoutKind
    /// for the contract).
    private var effectiveLayoutKind: LayoutKind {
        Self.effectiveLayoutKind(layout: layoutKind, lastVisible: lastVisibleLayoutKind)
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
        .padding(.horizontal, NotchMetrics.contentPaddingHorizontal)
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
        return HStack(spacing: 10) {
            Image(systemName: presentation.iconSystemName)
                .frame(width: 22)
                .symbolReplace(on: presentation.iconSystemName)
            HUDLevelSlider(kind: hud.kind, value: presentation.value, onChange: { hudSliderMoved(to: $0) }, isHovered: displayPolicy.pointerInside)
        }
        .padding(.horizontal, NotchMetrics.contentPaddingHorizontal)
    }
}
