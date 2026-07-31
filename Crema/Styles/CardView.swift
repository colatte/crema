import SwiftUI

/// Card skin view. Shape/content derive from `coordinator.state` (through the
/// display policy), live scrubber position from `coordinator.nowPlaying`,
/// intents go back as Coordinator method calls, no domain copies in @State.
/// The surface is sized per state and top-anchored inside the fixed window;
/// growth is vertical under one rounded-rectangle outline, and
/// compact/expanded hug their content's width between floor and ceiling
/// (HuggingWidthClamp + width key + rendered-size reporting).
@MainActor
struct CardView: View, SurfaceStyleBody {
    /// The shared surface vocabulary (SurfaceStyleCore); aliased so call sites
    /// and tests keep the per-skin spelling.
    typealias LayoutKind = SurfaceLayoutKind

    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    @Environment(\.surfaceStateSizes) private var stateSizes
    @Environment(\.surfaceSizeReporter) private var reportSurfaceSize

    /// Gates every surface morph to a dry landing (MG5) — see
    /// `SurfaceAnimation.geometryAnimation`; the opacity fade stays regardless.
    /// Not private: the shared motion gates (SurfaceStyleBody) read it.
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// Where the surface is coming from — the FROM of the current transition and
    /// the last VISIBLE layout the hidden surface freezes to (SurfaceProvenance
    /// carries the rule and the reasons). Ephemeral, purely visual: it never
    /// feeds the domain. Advanced in `onChange` AFTER the render that reads it —
    /// see the body comment for the evaluation-order subtlety.
    @State var provenance = SurfaceProvenance()

    var body: some View {
        Group {
            if let size = surfaceSize {
                // Adaptive states hug (nil width ⇒ intrinsic, clamped inside
                // `surface`); the HUD stays rule-sized.
                surface.frame(width: adaptiveWidth ? nil : size.width, height: size.height)
            } else {
                surface
            }
        }
        // The rendered size is the click-interactive truth: with the width
        // adaptive, the rule frame alone can't place the click region, so the
        // panel follows what is actually drawn.
        .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { size in
            reportSurfaceSize?(size)
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // This frame is geometry: it morphs only between visible layouts; an
        // appearance from or disappearance to `.empty` snaps it, so a HUD/card
        // born from hidden lands at its final rect instead of gliding in from the
        // invisible compact geometry (the surface radius snaps too, and the fade
        // lives on the opacity — both animated in `surface`). Here the gate
        // scopes the frame; the onChange below advances the provenance it reads
        // (it runs after this body, so it can't disturb this pass's read).
        .animation(geometryAnimation, value: layoutKind)
        // Width morphs when the track changes (the key derives from the state
        // payload, which ticks never rewrite) — never a bare jump; dry under
        // Reduce Motion like the geometry spring.
        .animation(SurfaceAnimation.morph(reduceMotion: reduceMotion), value: adaptiveWidthKey)
        // Toggling view-only resizes the card while it is open — animate it too.
        .animation(SurfaceAnimation.morph(reduceMotion: reduceMotion), value: showsControls)
        .onChange(of: layoutKind) { _, newValue in
            provenance.advance(to: newValue)
        }
    }

    var surface: some View {
        // The branches are direct subviews of the clamp (no ZStack in
        // between): only the active one drives the width measurement, so an
        // outgoing ghost — the HUD's greedy slider fading out over the
        // compact, say — can neither inflate the hug to the ceiling nor snap
        // the width, unanimated, when its removal completes. Each branch
        // carries its own sizing: hug states stay intrinsic, the HUD fills
        // its fixed rule size.
        HuggingWidthClamp(minWidth: adaptiveMinWidth, maxWidth: adaptiveMaxWidth, activeBranch: activeBranch) {
            content
        }
        // The content crossfade. This scope is closest to the branches, so it
        // wins over the radius snap above AND governs the bounds the material,
        // clip and stroke are sized off (vibrantSurface's `.background`/clip size
        // to the node below them — this clamp output). It is therefore
        // provenance-aware: nil on an appearance (the geometry snaps, no ghost
        // springs past the snapped outer frame; the content is invisible under
        // opacity 0 and fades in with the surface), the directional spring on a
        // disappearance (the glyph fades out instead of popping) and between
        // visible layouts (the HUD↔now-playing crossfade + morph). It wraps the
        // clamp's output, never the branch switch, so the active-branch
        // measurement is intact.
        .animation(contentAnimation, value: layoutKind)
        // Outside the clamp: wrapping the branch switch would collapse the
        // branches into one subview and break the active-branch measurement;
        // riding above them also keeps the accent state across
        // compact↔expanded.
        .artworkAccent(from: accentArtwork)
        // One morphing outline for every state: the radius is state-dependent
        // (the short HUD would read as a capsule at the now-playing radius).
        .vibrantSurface(in: RoundedRectangle(cornerRadius: surfaceCornerRadius, style: .continuous))
        // Radius is geometry: it morphs HUD↔now-playing but SNAPS on an
        // appearance from or disappearance to hidden. Keyed on the radius VALUE so
        // it fires only when the corner actually changes (never on a same-radius
        // appear), and it sits above the clamp, so it drives the corner without
        // overriding the content crossfade's own inner scope.
        .animation(geometryAnimation, value: surfaceCornerRadius)
        .opacity(layoutKind == .empty ? 0 : 1)
        // The appearance/disappearance fade: opacity keeps its spring even when
        // the geometry snaps, so a surface born from hidden fades in at its final
        // frame instead of gliding in. Only fires on empty↔visible (opacity is 1
        // across every visible transition), so its animation choice never touches
        // a visible→visible morph.
        .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
        // Pinned dark ENCLOSING vibrantSurface (the environment reaches the
        // AppKit-backed material): per-branch scoping would flip the palette
        // mid HUD↔now-playing morph (docs/DECISIONS.md: hud-fixed-dark-palette).
        .environment(\.colorScheme, .dark)
    }

    /// The HUD gets its own smaller radius (rounded rectangle, not capsule); every
    /// now-playing state keeps the generous card radius. Animatable, so the change
    /// morphs under the surface spring. Keyed on the EFFECTIVE layout, so a hidden
    /// surface keeps the radius it faded out with (empty-after-hud stays 12).
    private var surfaceCornerRadius: CGFloat {
        Self.surfaceCornerRadius(for: effectiveLayoutKind)
    }

    nonisolated static func surfaceCornerRadius(for kind: LayoutKind) -> CGFloat {
        kind == .hud ? CardMetrics.hudSystemCornerRadius : CardMetrics.cornerRadius
    }

    private var adaptiveMinWidth: CGFloat? {
        switch effectiveLayoutKind {
        case .compact, .empty: CardMetrics.compactMinWidth
        case .expanded: CardMetrics.expandedMinWidth
        case .hud: nil
        }
    }

    private var adaptiveMaxWidth: CGFloat? {
        switch effectiveLayoutKind {
        case .compact, .empty: CardMetrics.compactMaxWidth
        case .expanded: CardMetrics.expandedMaxWidth
        case .hud: nil
        }
    }

    /// True while the surface hugs its content (nil width in `body` ⇒ the
    /// clamp decides); the HUD fills its fixed rule size. Keyed on the EFFECTIVE
    /// layout so a hidden surface freezes the outgoing layout's width discipline
    /// (empty-after-hud stays fixed-width, not hugging).
    private var adaptiveWidth: Bool {
        switch effectiveLayoutKind {
        case .compact, .empty, .expanded: true
        case .hud: false
        }
    }

    private var activeBranch: String {
        switch layoutKind {
        case .empty: "empty"
        case .compact: "compact"
        case .expanded: "expanded"
        case .hud: "hud"
        }
    }

    var adaptiveWidthKey: String? {
        contentKind.adaptiveWidthKey
    }

    /// The crossfading branches, each carrying a constant SurfaceBranch tag
    /// (a removal-frozen ghost keeps the tag it was built with — that is what
    /// lets the clamp tell the ghost from the active branch).
    @ViewBuilder private var content: some View {
        switch contentKind {
        case .empty:
            // Fills whatever the effective layout proposes: while hidden the
            // surface freezes the outgoing rect, so the empty branch must adopt
            // that width (empty-after-hud fills the 210 rule width) rather than
            // pinning to the compact floor — a fixed floor here snapped the
            // material narrower the instant a HUD began fading out. The adaptive
            // states still collapse to the floor: the clamp's provenance-aware
            // minWidth pins them, not this branch.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutValue(key: SurfaceBranch.self, value: "empty")
        case .nowPlayingCompact(let track):
            compactContent(track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .layoutValue(key: SurfaceBranch.self, value: "compact")
        case .nowPlayingExpanded(let track):
            expandedContent(track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .layoutValue(key: SurfaceBranch.self, value: "expanded")
        case .hud(let hud):
            hudContent(hud)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .layoutValue(key: SurfaceBranch.self, value: "hud")
        }
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
            controlsSectionHeight: CardMetrics.controlsSectionHeight
        )
    }

    nonisolated static func effectiveLayoutKind(layout: LayoutKind, lastVisible: LayoutKind) -> LayoutKind {
        SurfaceLayout.effectiveLayoutKind(layout: layout, lastVisible: lastVisible)
    }

    /// Binds the shared freeze rule to this view's provenance @State
    /// (see SurfaceLayout.effectiveLayoutKind for the contract).
    private var effectiveLayoutKind: LayoutKind {
        Self.effectiveLayoutKind(layout: layoutKind, lastVisible: provenance.lastVisible)
    }

    // MARK: - Rendering

    // The text takes the flexible role (not a Spacer, whose neighbors would
    // each get their own HStack spacing — a double gap): under the clamp's
    // ideal-width measurement it still reports the text's ideal, and at
    // placement it absorbs the slack, pinning the waveform to the trailing
    // edge whenever the floor makes the surface wider than the row.
    private func compactContent(_ track: NowPlaying) -> some View {
        HStack(spacing: CardMetrics.contentGap) {
            ArtworkView(
                data: track.artworkData,
                side: CardMetrics.compactArtworkSide,
                cornerRadius: CardMetrics.compactArtworkRadius
            )
            TrackTextStack(title: track.title, artist: track.artist, spacing: CardMetrics.textStackSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Compact only: here it is the sole "playing" signal. Expanded
            // already says it twice (scrubber motion + pause glyph).
            WaveformGlyph(animating: track.isPlaying)
        }
        .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
    }

    private func expandedContent(_ track: NowPlaying) -> some View {
        // The family's reference layout (design-reference §4.1, the Dynamic
        // Island/Live Activities pattern): artwork anchors the top-left with
        // the stacked title/artist beside it, the thin scrubber spans the
        // width, and the transport block sits grouped at the base. Every row
        // has a fixed height and the expanded frame is their exact sum
        // (CardMetrics.expanded), so there is no slack to pool into dead
        // space between sections.
        //
        // Only the header is in-flow: it is the width driver the hugging
        // clamp measures, and it fills the resolved width so the artwork
        // pins to the real leading edge at any hug. The spanning scrubber
        // and the centered transport render in overlays over rows reserved
        // by bottom padding — their widths are system values (the slider's
        // ideal is not ours to control), so in-flow they would jitter the
        // hug; the width floor they need is CardMetrics.expandedMinWidth.
        HStack(spacing: CardMetrics.contentGap) {
            ArtworkView(
                data: track.artworkData,
                side: CardMetrics.expandedArtworkSide,
                cornerRadius: CardMetrics.expandedArtworkRadius
            )
            TrackTextStack(title: track.title, artist: track.artist, spacing: CardMetrics.textStackSpacing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: CardMetrics.expandedArtworkSide)
        .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
        .padding(.top, CardMetrics.contentPaddingVertical)
        // Reserves the rows below the header. View-only drops the controls
        // section from the reservation just as the surface height drops it, so
        // the scrubber lands at the base with no pooled gap.
        .padding(
            .bottom,
            showsControls
                ? CardMetrics.contentPaddingVertical
                + CardMetrics.controlsHeight
                + CardMetrics.contentGap
                + CardMetrics.scrubberRowHeight
                + CardMetrics.contentGap
                : CardMetrics.contentPaddingVertical
                + CardMetrics.scrubberRowHeight
                + CardMetrics.contentGap
        )
        .overlay(alignment: .bottom) {
            if showsControls {
                TransportControls(
                    isPlaying: track.isPlaying,
                    enabled: controlsEnabled,
                    skipEnabled: skipControlsEnabled,
                    buttonSide: CardMetrics.controlsHeight,
                    onPrevious: { previousTapped() },
                    onPlayPause: { playPauseTapped() },
                    onNext: { nextTapped() }
                )
                .padding(.bottom, CardMetrics.contentPaddingVertical)
            }
        }
        .overlay(alignment: .bottom) {
            scrubber
                .frame(height: CardMetrics.scrubberRowHeight)
                .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
                .padding(.bottom, showsControls
                    ? CardMetrics.contentPaddingVertical + CardMetrics.controlsHeight + CardMetrics.contentGap
                    : CardMetrics.contentPaddingVertical)
        }
    }

    private var scrubber: some View {
        ScrubberRow(
            position: scrubberPosition,
            duration: scrubberDuration,
            enabled: controlsEnabled,
            showsDuration: true,
            onScrub: { scrubbed(to: $0) }
        )
    }

    @ViewBuilder private func hudContent(_ hud: SystemHUD) -> some View {
        let presentation = HUDPresentation(hud: hud)
        switch displayPolicy.hudIndicatorStyle {
        case .slider:
            // Icon beside the capsule row (the Notch's layout too); Classic keeps its bezel's segmented bar.
            HStack(spacing: CardMetrics.contentGap) {
                Image(systemName: presentation.iconSystemName)
                    .frame(width: CardMetrics.hudIconColumnWidth)
                    .symbolReplace(on: presentation.iconSystemName)
                HUDLevelSlider(
                    kind: hud.kind,
                    value: presentation.value,
                    onChange: { hudSliderMoved(to: $0) },
                    onRelease: { hudSliderReleased() },
                    appearance: HUDLevelSlider.appearance(for: displayPolicy.hudIndicatorStyle),
                    isHovered: displayPolicy.pointerInside
                )
            }
            .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
        case .filled:
            // Fused, full-bleed: the bar fills the whole HUD frame (no padding,
            // no inner track) and the card's rounded-rect clip (vibrantSurface)
            // rounds the sweep. The icon rides inside at the leading edge, over
            // the fill at high levels and the dark remainder at low ones.
            HUDLevelSlider(
                kind: hud.kind,
                value: presentation.value,
                onChange: { hudSliderMoved(to: $0) },
                onRelease: { hudSliderReleased() },
                appearance: .filled
            )
            .overlay(alignment: .leading) {
                Image(systemName: presentation.iconSystemName)
                    .foregroundStyle(CardMetrics.hudFilledIconColor)
                    .padding(.leading, CardMetrics.hudFilledIconLeading)
                    .accessibilityHidden(true)
                    // The bar underneath owns the whole drag/tap surface; the
                    // glyph is decoration and must let touches through to it.
                    .allowsHitTesting(false)
                    // Overlay glyph — a separate subtree from the fill below, so
                    // the swap animates the icon without touching the bar.
                    .symbolReplace(on: presentation.iconSystemName)
            }
        }
    }
}
