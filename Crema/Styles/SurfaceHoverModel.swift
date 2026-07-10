import CoreGraphics

/// Screen-space hover regions with spatial hysteresis. A smaller enter region
/// (the resting/compact surface) and a larger exit region (the expanded surface
/// widened by a margin) decouple hover detection from the frame the panel
/// animates through: a still cursor is judged against these stable rects, not
/// the surface edge that sweeps under it while the window resizes. That sweep,
/// read by a single in/out threshold, was the open/close loop.
struct SurfaceHoverRegions: Equatable {
    /// How far past the expanded edge the cursor must travel before the surface
    /// counts as left — the spatial half of the hysteresis.
    static let defaultExitMargin: CGFloat = 24

    /// A few points of slack around the visible surface so hover arms as the
    /// cursor reaches the drawn edge, not on a pixel-perfect hit — deliberate
    /// breathing room, distinct from the larger sticky exit band. Legitimate
    /// comfort; the bug it replaces was the rule ceiling overshooting the
    /// adaptive card by tens of points per side.
    static let comfortMargin: CGFloat = 6

    /// Entering here starts a hover (the compact surface's bounds).
    var enter: CGRect
    /// The cursor must leave here to end a hover (expanded bounds + margin).
    /// Contains `enter`, so the gap between them is a sticky dead band.
    var exit: CGRect

    /// Regions clipped to a surface actually rendered on screen: `enter` is the
    /// visible rect widened by the comfort margin, `exit` adds the sticky
    /// hysteresis band. The width-hugging card reports a surface narrower than
    /// its rule ceiling, so deriving hover from the drawn rect — the same
    /// rendered truth the click region uses — keeps hover from arming in the
    /// dead air beside the visible card. `exit` contains `enter` by exactly
    /// `exitMargin`, so the band is always sticky.
    static func around(_ surface: CGRect, exitMargin: CGFloat = defaultExitMargin) -> Self {
        Self(
            enter: surface.insetBy(dx: -comfortMargin, dy: -comfortMargin),
            exit: surface.insetBy(dx: -(comfortMargin + exitMargin), dy: -(comfortMargin + exitMargin))
        )
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
