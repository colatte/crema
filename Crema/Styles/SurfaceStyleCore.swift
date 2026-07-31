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
/// feeds `controlsSectionHeight` (docs/DECISIONS.md: shared-skin-skeleton).
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

/// Where the surface is coming FROM: the provenance the motion gates and the
/// empty-boundary freeze both read. Two fields rather than one, because they
/// answer different questions — `previous` advances to `.empty` as well (an
/// appearance is not a morph), while `lastVisible` has to survive the whole
/// hidden period; a single field would flip the frozen rect to compact one
/// render into the fade. The storage stays in each view (@State: ephemeral,
/// purely visual, never domain) and only this rule is shared, so an advance fix
/// cannot land on two skins and miss the third
/// (docs/DECISIONS.md: shared-skin-skeleton).
struct SurfaceProvenance: Equatable {
    /// `.empty` before anything has shown, which reads the first appearance as
    /// what it is: a crossing of the empty boundary.
    var previous: SurfaceLayoutKind = .empty
    /// Compact until something has shown — the fallback `effectiveLayoutKind`
    /// documents.
    var lastVisible: SurfaceLayoutKind = .compact

    /// Advanced AFTER the render that read it (each view's `onChange`), so the
    /// body pass animating a transition still sees its true FROM.
    mutating func advance(to kind: SurfaceLayoutKind) {
        previous = kind
        if kind != .empty { lastVisible = kind }
    }
}

/// The non-visual skeleton every skin shares: state in (content/layout
/// derivation off the Coordinator, through the display policy), motion gates
/// (provenance + the accessibility preference in, animation out) and intent out
/// (Coordinator method passthroughs — what the unit tests invoke directly).
/// A skin conforms and keeps only its visual body plus the two pieces of
/// per-view storage the rules read — SwiftUI owns those — and the one-line
/// statics that fix its Metrics parameter.
@MainActor
protocol SurfaceStyleBody {
    var coordinator: Coordinator { get }
    var displayPolicy: SurfaceDisplayPolicy { get }
    /// The view's provenance @State: storage has to live in the view, the
    /// advance rule and everything derived from it do not.
    var provenance: SurfaceProvenance { get }
    /// Read from each view's environment (`accessibilityReduceMotion`); the
    /// gate it feeds is app-wide and lives in SurfaceAnimation alone.
    var reduceMotion: Bool { get }
}

extension SurfaceStyleBody {

    // MARK: - Content derivation (state in)

    var contentKind: StyleContent {
        StyleContent(
            state: coordinator.state,
            showsNowPlaying: displayPolicy.showsNowPlaying,
            showsHUD: displayPolicy.showsHUD
        )
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

    // MARK: - Motion gates (provenance in, animation out)

    /// The surface's GEOMETRY animation — the frame plus whatever geometry each
    /// skin scopes to it (the Card's corner radius, the Notch's flare), never
    /// the opacity: morph between visible layouts, snap across the empty
    /// boundary, dry under Reduce Motion. It reads `provenance.previous`, which
    /// still holds the OLD kind during the body pass that first sees the new
    /// `layoutKind` — `.animation(_:value:)` samples its animation argument at
    /// that pass, so the transition's true provenance is what gates it.
    var geometryAnimation: Animation? {
        SurfaceAnimation.geometryAnimation(
            fromEmpty: provenance.previous == .empty,
            toEmpty: layoutKind == .empty,
            expanding: isExpanded,
            reduceMotion: reduceMotion
        )
    }

    /// The content crossfade's animation, whose scope also sizes the material,
    /// clip and stroke: nil on an appearance so those snap to the destination
    /// instead of springing past the snapped outer frame, the directional spring
    /// otherwise so outgoing content fades instead of popping
    /// (see `SurfaceAnimation.contentAnimation`).
    var contentAnimation: Animation? {
        SurfaceAnimation.contentAnimation(
            fromEmpty: provenance.previous == .empty,
            expanding: isExpanded,
            reduceMotion: reduceMotion
        )
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

    func hudSliderReleased() {
        coordinator.hudSliderReleased()
    }
}
