import SwiftUI

/// Card skin view. Shape/content derive from `coordinator.state` (through the
/// display policy), live scrubber position from `coordinator.nowPlaying`,
/// intents go back as Coordinator method calls, no domain copies in @State.
/// The surface is sized per state and top-anchored inside the fixed window;
/// growth is vertical under one rounded-rectangle outline, and
/// compact/expanded hug their content's width between floor and ceiling
/// (HuggingWidthClamp + width key + rendered-size reporting).
@MainActor
struct CardView: View {
    let coordinator: Coordinator
    var displayPolicy = SurfaceDisplayPolicy()

    @Environment(\.surfaceStateSizes) private var stateSizes
    @Environment(\.surfaceSizeReporter) private var reportSurfaceSize

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
        // Keyed on layoutKind so value ticks don't animate; direction picks the
        // spring.
        .animation(isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close, value: layoutKind)
        // Width morphs when the track changes (the key derives from the state
        // payload, which ticks never rewrite) — never a bare jump.
        .animation(SurfaceAnimation.open, value: adaptiveWidthKey)
        // Toggling view-only resizes the card while it is open — animate it too.
        .animation(SurfaceAnimation.open, value: showsControls)
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
        // Outside the clamp: wrapping the branch switch would collapse the
        // branches into one subview and break the active-branch measurement;
        // riding above them also keeps the accent state across
        // compact↔expanded.
        .artworkAccent(from: accentArtwork)
        .vibrantSurface(in: RoundedRectangle(cornerRadius: CardMetrics.cornerRadius, style: .continuous))
        .opacity(layoutKind == .empty ? 0 : 1)
    }

    private var adaptiveMinWidth: CGFloat? {
        switch layoutKind {
        case .compact, .empty: CardMetrics.compactMinWidth
        case .expanded: CardMetrics.expandedMinWidth
        case .hud: nil
        }
    }

    private var adaptiveMaxWidth: CGFloat? {
        switch layoutKind {
        case .compact, .empty: CardMetrics.compactMaxWidth
        case .expanded: CardMetrics.expandedMaxWidth
        case .hud: nil
        }
    }

    /// True while the surface hugs its content (nil width in `body` ⇒ the
    /// clamp decides); the HUD fills its fixed rule size.
    private var adaptiveWidth: Bool {
        switch layoutKind {
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
            // Pinned to the floor: Color fills whatever is proposed, and
            // the empty fade should collapse to the floor, not stretch to
            // the ceiling.
            Color.clear
                .frame(width: CardMetrics.compactMinWidth)
                .frame(maxHeight: .infinity)
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
        switch layoutKind {
        case .empty, .compact: return stateSizes.compact
        case .expanded: return expandedSurfaceSize(stateSizes.expanded)
        case .hud: return stateSizes.hud
        }
    }

    /// View-only shrinks the expanded card by exactly the controls section, so
    /// the visible sections fill it with no dead space; the fixed window is
    /// unchanged (always larger than any state).
    private func expandedSurfaceSize(_ full: CGSize) -> CGSize {
        guard !showsControls else { return full }
        return CGSize(width: full.width, height: full.height - CardMetrics.controlsSectionHeight)
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

    /// View-only mode (Settings): the expanded surface drops the transport row
    /// and shrinks by exactly that section (expandedSurfaceSize), so the visible
    /// sections fill it with no pooled gap.
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
            WaveformGlyph(animating: track.isPlaying, config: CardMetrics.waveform)
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

    private func hudContent(_ hud: SystemHUD) -> some View {
        let presentation = HUDPresentation(hud: hud)
        return HStack(spacing: CardMetrics.contentGap) {
            Image(systemName: presentation.iconSystemName)
                .frame(width: 22)
            HUDLevelSlider(kind: hud.kind, value: presentation.value, onChange: { hudSliderMoved(to: $0) })
        }
        .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
    }
}
