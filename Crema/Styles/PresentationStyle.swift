import CoreGraphics
import SwiftUI

/// One skin = a SwiftUI view + a pure rule for the hosting panel's frame.
/// New styles plug in without touching Sources/Domain/Coordinator. Runtime
/// dispatch across the closed set of skins lives in the `Style` enum; this
/// protocol is the per-style contract it dispatches to.
protocol PresentationStyle {
    associatedtype StyleView: View

    /// Pure function of (state, geometry): where the panel lives and how big
    /// it is. Receives ScreenGeometry — never NSScreen — so it's unit-testable;
    /// the WindowManager applies the result to the NSPanel by hand.
    func frame(for state: PresentationState, on geometry: ScreenGeometry) -> CGRect

    /// The skin's view. Reads `coordinator.state`/`coordinator.nowPlaying`
    /// (through the display policy — per-display now-playing suppression) and
    /// reports intents back as Coordinator method calls.
    @MainActor @ViewBuilder func makeView(coordinator: Coordinator, displayPolicy: SurfaceDisplayPolicy) -> StyleView

    /// The panel's fixed window frame. A protocol requirement (not just an
    /// extension method) so a style with a different anchor — classic pins its
    /// bottom — dispatches dynamically through `any PresentationStyle` too.
    func windowFrame(on geometry: ScreenGeometry) -> CGRect

    /// Per-edge hover exit band. A protocol requirement for the same reason as
    /// `windowFrame`: the notch's directional override must dispatch
    /// dynamically when the extension's own `hoverRegions` reads it.
    var hoverExitMargins: SurfaceHoverRegions.Margins { get }
}

/// Throwaway payloads for probing the frame rule: every rule sizes purely from
/// the state's case and geometry, so the payloads never reach the result.
private let referenceTrack = NowPlaying(title: "", isPlaying: true, position: 0)
private let referenceHUD = SystemHUD(kind: .volume, value: 0)

extension PresentationStyle {
    /// The per-edge sticky exit band this style's regions use. Uniform by
    /// default; a style whose edges sit on different neighbors (the notch,
    /// flanked by live menu bar) overrides with directional values.
    var hoverExitMargins: SurfaceHoverRegions.Margins { .uniform }

    /// Initial hover regions in screen coordinates — a seed only: the panel
    /// retargets to the CURRENT state/rendered surface on every apply and size
    /// report, so the exit band always hugs what the eye sees. Exit contains
    /// enter by construction (`around`), preserving the hysteresis; the old
    /// union across states left a 100 pt invisible sticky band below the
    /// compact notch where a resting cursor held the surface forever
    /// (docs/DECISIONS.md: hover-follows-the-eye). Nil when the style has no
    /// distinct expanded surface to hover into (compact == expanded).
    func hoverRegions(on geometry: ScreenGeometry) -> SurfaceHoverRegions? {
        let compact = frame(for: .nowPlaying(referenceTrack, expanded: false), on: geometry)
        let expanded = frame(for: .nowPlaying(referenceTrack, expanded: true), on: geometry)
        guard !compact.isEmpty, !expanded.isEmpty, compact != expanded else { return nil }
        return .around(compact, margins: hoverExitMargins)
    }

    /// The click-invoke zone: where a click surfaces a tucked appearance.
    /// Nil by default — a floating style's region sits over live app content
    /// (window toolbars, desktop), and capturing clicks there would steal
    /// interactions that belong to what's below. Only a style whose region is
    /// genuinely dead territory (the notch's physical slit) overrides this.
    func invokeZone(on geometry: ScreenGeometry) -> CGRect? {
        nil
    }

    /// Surface size per state, straight from the frame rule — injected into the
    /// view so it can size the surface within the fixed window.
    func stateSizes(on geometry: ScreenGeometry) -> SurfaceStateSizes {
        SurfaceStateSizes(
            compact: frame(for: .nowPlaying(referenceTrack, expanded: false), on: geometry).size,
            expanded: frame(for: .nowPlaying(referenceTrack, expanded: true), on: geometry).size,
            hud: frame(for: .hud(referenceHUD), on: geometry).size
        )
    }

    /// The panel's fixed frame: the union of every state's rule frame — no
    /// single state is guaranteed largest on both axes — plus overshoot headroom,
    /// sideways and down only; the top edge stays pinned so the top-anchored
    /// surface sits exactly where the rule puts it. The window never resizes
    /// after creation; states animate as content inside it, so there is no
    /// window-vs-render race to coordinate.
    func windowFrame(on geometry: ScreenGeometry) -> CGRect {
        var rect = frame(for: .nowPlaying(referenceTrack, expanded: true), on: geometry)
            .union(frame(for: .nowPlaying(referenceTrack, expanded: false), on: geometry))
            .union(frame(for: .hud(referenceHUD), on: geometry))
        rect.origin.x -= SurfaceAnimation.overshootHeadroom
        rect.size.width += 2 * SurfaceAnimation.overshootHeadroom
        rect.origin.y -= SurfaceAnimation.overshootHeadroom
        rect.size.height += SurfaceAnimation.overshootHeadroom
        return rect
    }
}
