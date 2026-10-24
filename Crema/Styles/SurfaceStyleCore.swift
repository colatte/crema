import SwiftUI

/// The surface's layout identity, independent of the HUD/track value — shared
/// by every skin (each aliases it as `LayoutKind`), so the morph animation
/// fires on compact↔expanded↔hud transitions but never on the once-per-second
/// position tick or a HUD level change.
enum SurfaceLayoutKind: Equatable {
    case empty, compact, expanded, hud

    init(_ content: StyleContent) {
        switch content {
        case .empty: self = .empty
        case .nowPlayingCompact: self = .compact
        case .nowPlayingExpanded: self = .expanded
        case .hud: self = .hud
        }
    }
}

/// The pure layout rules every skin shares — one implementation, so a contract
/// fix cannot land on two skins and miss the third, the failure a per-skin copy
/// of the empty-boundary freeze invites. Each view keeps a one-line static
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

    /// The content the surface draws: what it shows, and while it is hidden the
    /// content it last showed, so a disappearance changes the surface's opacity
    /// alone. Hidden and shown are two states of one surface, not two views:
    /// removed as a branch, the content took a fade of its own under the
    /// surface's, and opacities multiply, so it went out at the square of the
    /// surface's opacity, ahead of its outline (SwiftUI, `View.opacity(_:)`:
    /// "multiplies the effect of the underlying opacity transformation"; WWDC21
    /// "Demystify SwiftUI", session 10022: "try to preserve identity").
    nonisolated static func drawnContent(_ content: StyleContent, lastVisible: StyleContent) -> StyleContent {
        content == .empty ? lastVisible : content
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
/// empty-boundary freeze both read. Two layout fields rather than one, because
/// they answer different questions — `previous` advances to `.empty` as well (an
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
    /// What a hidden surface draws while it fades (`SurfaceLayout.drawnContent`).
    var lastVisibleContent: StyleContent = .empty

    /// Advanced AFTER the render that read it (each view's `onChange`), so the
    /// body pass animating a transition still sees its true FROM.
    mutating func advance(to content: StyleContent) {
        let kind = SurfaceLayoutKind(content)
        previous = kind
        if kind != .empty {
            lastVisible = kind
            lastVisibleContent = content
        }
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

    /// What this panel shows of the Coordinator's layers: both on a skin's own
    /// panel, one where the Card's HUD has a panel of its own; the appearance under
    /// a HUD this display does not show.
    var presentedState: PresentationState {
        coordinator.layers.state(on: displayPolicy.surface, showsHUD: displayPolicy.showsHUD)
    }

    var contentKind: StyleContent {
        StyleContent(state: presentedState, showsNowPlaying: displayPolicy.showsNowPlaying)
    }

    var layoutKind: SurfaceLayoutKind {
        SurfaceLayoutKind(contentKind)
    }

    /// What the surface draws (`SurfaceLayout.drawnContent`).
    var drawnContent: StyleContent {
        SurfaceLayout.drawnContent(contentKind, lastVisible: provenance.lastVisibleContent)
    }

    var isExpanded: Bool {
        if case .nowPlaying(_, expanded: true) = presentedState { return true }
        return false
    }

    /// Artwork bytes behind the cover and the accent — from the state payload
    /// (ticks never rewrite it); nil under a HUD, and a hidden surface keeps the
    /// cover it fades out with (`drawnContent`).
    var coverArtwork: [UInt8]? {
        switch drawnContent {
        case .nowPlayingCompact(let track), .nowPlayingExpanded(let track):
            track.artworkData
        case .empty, .hud:
            nil
        }
    }

    /// Controls are offered only while the write path works and the track is a
    /// player's; otherwise the surface is read-only (no button that silently
    /// does nothing).
    var controlsEnabled: Bool {
        coordinator.controlsEnabled
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

    /// The appearance/disappearance fade, on the surface's opacity: the spring
    /// chosen by the destination, and never gated by Reduce Motion — a
    /// cross-fade is what that preference asks for in place of motion.
    ///
    /// `.animation(_:value:)` applies "whenever `value` changes" (SwiftUI,
    /// `View.animation(_:value:)`), so keyed on `layoutKind` this rides every
    /// visible→visible change too, into whatever below it has no closer scope.
    /// The opacity itself does not change there; what keeps the fade from
    /// deciding a morph is that each skin puts its geometry and content under
    /// their own scopes (`geometryAnimation`, `contentAnimation`), which are the
    /// ones that go dry under Reduce Motion.
    var fadeAnimation: Animation {
        isExpanded ? SurfaceAnimation.open : SurfaceAnimation.close
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

private struct SurfaceIsShownKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// Whether the surface drawing this view is shown. A hidden surface still
    /// draws the content it faded out with (`SurfaceLayout.drawnContent`), so
    /// what loops on it stops: nothing new is drawn where nobody sees it.
    var surfaceIsShown: Bool {
        get { self[SurfaceIsShownKey.self] }
        set { self[SurfaceIsShownKey.self] = newValue }
    }
}
