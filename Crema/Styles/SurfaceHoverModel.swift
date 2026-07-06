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

    /// Entering here starts a hover (the compact surface's bounds).
    var enter: CGRect
    /// The cursor must leave here to end a hover (expanded bounds + margin).
    /// Contains `enter`, so the gap between them is a sticky dead band.
    var exit: CGRect
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
