import CoreGraphics

/// Screen-space hover regions with spatial hysteresis. A smaller enter region
/// (the visible surface plus comfort) and a larger exit region (enter plus the
/// sticky band) decouple hover detection from the frame the panel animates
/// through: a still cursor is judged against these stable rects, not the
/// surface edge that sweeps under it while the window resizes. That sweep,
/// read by a single in/out threshold, was the open/close loop.
///
/// The regions are retargeted per state/rendered surface (the panel pushes on
/// every apply and size report), so the exit band is a thin margin around what
/// the eye currently sees — never a union of states. The state-blind union was
/// the stuck-hover bug: a 100 pt invisible band below the compact notch where
/// a resting cursor held the surface forever (docs/DECISIONS.md:
/// hover-follows-the-eye).
struct SurfaceHoverRegions: Equatable {
    /// Per-edge sticky band beyond `enter`, in screen coordinates (y up:
    /// `bottom` extends minY, `top` extends maxY). Directional because the
    /// edges differ in what they sit on: laterally the band lands on live
    /// pixels (the menu bar flanking the notch), below it hangs over app
    /// content, and a top-anchored surface's top edge never moves. Every
    /// band on an edge that can move must absorb the open spring's overshoot
    /// (comfort + margin ≥ SurfaceAnimation.overshootHeadroom — pinned).
    struct Margins: Equatable {
        var top: CGFloat
        var lateral: CGFloat
        var bottom: CGFloat

        /// The default band: 10 pt beyond comfort on every edge.
        static let uniform = Self(top: 10, lateral: 10, bottom: 10)
    }

    /// A few points of slack around the visible surface so hover arms as the
    /// cursor reaches the drawn edge, not on a pixel-perfect hit — deliberate
    /// breathing room, distinct from the sticky exit band.
    static let comfortMargin: CGFloat = 6

    /// Entering here starts a hover (visible surface + comfort).
    var enter: CGRect
    /// The cursor must leave here to end a hover (enter + margins).
    /// Contains `enter` by construction, so the gap is a sticky dead band.
    var exit: CGRect

    /// The apply-time region: the current state's rule frame intersected with
    /// the last rendered truth when one exists. Errs TIGHT on purpose — during
    /// the frame before the new size report lands, an under-armed region is
    /// harmless (the report widens it), while either stale rect alone
    /// re-creates a closed bug: the previous state's silhouette held the stuck
    /// band, and the bare rule ceiling re-armed the card's dead air. Nil when
    /// the intersection is degenerate (keep the last regions).
    static func forApply(ruleFrame: CGRect, lastRendered: CGRect?, margins: Margins) -> Self? {
        let base = lastRendered.map { $0.intersection(ruleFrame) } ?? ruleFrame
        guard !base.isEmpty else { return nil }
        return .around(base, margins: margins)
    }

    /// Regions around a surface actually rendered on screen: `enter` is the
    /// visible rect widened by the comfort margin, `exit` adds the directional
    /// sticky band. Hover and clicks derive from the same rendered truth
    /// (docs/DECISIONS.md: hover-follows-the-eye).
    static func around(_ surface: CGRect, margins: Margins = .uniform) -> Self {
        let enter = surface.insetBy(dx: -comfortMargin, dy: -comfortMargin)
        let exit = CGRect(
            x: enter.minX - margins.lateral,
            y: enter.minY - margins.bottom,
            width: enter.width + 2 * margins.lateral,
            height: enter.height + margins.bottom + margins.top
        )
        return Self(enter: enter, exit: exit)
    }
}

/// Pure hover decision with hysteresis: while outside, the cursor must reach
/// `enter` to turn on; while inside, it must leave `exit` to turn off. In the
/// band between them it keeps its prior answer, so a cursor idling at the compact
/// edge — or the resize animation sweeping the frame under it — cannot oscillate.
/// No window frame and no clock: a plain function of the cursor, the last answer,
/// and the stable regions, so the anti-loop behavior is unit-testable.
struct SurfaceHoverModel {
    let regions: SurfaceHoverRegions

    func isInside(_ point: CGPoint, wasInside: Bool) -> Bool {
        wasInside ? regions.exit.contains(point) : regions.enter.contains(point)
    }
}
