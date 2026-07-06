import SwiftUI

/// Calibratable animation values for the presentation surfaces, isolated in
/// one place (design-reference §2.2/§2.3). Every value is a starting point to
/// tune on hardware, not an absolute.
///
/// All visible motion is SwiftUI's: the view morphs a sized surface inside a
/// fixed window (see NSPanelPresentationPanel). One animator, so nothing fights.
enum SurfaceAnimation {
    /// Spring parameters. Open is livelier; close is critically damped — never
    /// overshoot on close, or the bounce against the static menu bar reads as
    /// instability.
    static let openResponse: Double = 0.42
    static let openDamping: Double = 0.8
    static let closeResponse: Double = 0.45
    static let closeDamping: Double = 1.0

    /// Surface morph springs, chosen by direction: the destination state selects
    /// the spring (see the views).
    static let open: Animation = .spring(response: openResponse, dampingFraction: openDamping)
    static let close: Animation = .spring(response: closeResponse, dampingFraction: closeDamping)

    /// Headroom the fixed window keeps past the expanded frame (sideways and
    /// down; the top anchor stays pinned): the open spring's overshoot carries
    /// the surface a few points past its target, and without headroom the
    /// window edge would crop the peak.
    static let overshootHeadroom: CGFloat = 12

    /// How long a shrinking surface's old extent stays click-interactive: the
    /// close spring's visible settle (≥ 1.5 × response). Tightening earlier
    /// would forward clicks through still-visible pixels to the window below.
    static let interactiveSettle: Double = 0.7

    /// Post-close suppression window (design-reference §2.3): the time to ignore
    /// a hover-open right after the surface is dismissed programmatically.
    /// Reserved and not wired — the committed-hover model already restores the
    /// correct expanded state on HUD revert and resets it on hide (see the
    /// Coordinator), and wiring it into the HUD path would perturb that timer's
    /// exact-delay tests. Kept here so the value has one home when revisited.
    static let postCloseSuppression: Double = 0.35
}
