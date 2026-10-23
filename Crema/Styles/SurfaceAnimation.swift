import SwiftUI

/// Calibratable animation values for the presentation surfaces, isolated in
/// one place. Every value is a starting point to
/// tune on hardware, not an absolute.
///
/// All visible motion is SwiftUI's: the view morphs a sized surface inside a
/// fixed window (see NSPanelPresentationPanel). One animator, so nothing fights.
///
/// Scope rule: values that participate in the presentation contracts live here
/// (the directional morph springs, appear/dismiss, the level glide calibrated
/// against the HUD revert); a component's private affordance timing lives in
/// the component (WaveformGlyph.freezeDuration, ArtworkAccent.toneFadeDuration,
/// CapsuleTrack.knobReveal).
enum SurfaceAnimation {
    /// Spring parameters. Open is livelier; close is critically damped — never
    /// overshoot on close, or the bounce against the static menu bar reads as
    /// instability.
    private static let openResponse: Double = 0.42
    static let openDamping: Double = 0.8
    // 0.35, set 2026-07-27 (9dd6629) from the release-latency budget: t90 279 →
    // 217 ms against the 0.45 it replaced, measured with the hover exit timing of
    // that day (docs/DECISIONS.md: hover-follows-the-eye); no probe is kept in the
    // tree. Invalidating signal: a change to the hover exit timing
    // (`hoverExitRelinger`, the exit margins), or a close that reads late against
    // the pointer on hardware. Damping stays 1.0 — no overshoot against the menu bar.
    private static let closeResponse: Double = 0.35
    static let closeDamping: Double = 1.0

    /// Surface morph springs, chosen by direction: the destination state selects
    /// the spring (see the views). The appearance/disappearance opacity fade uses
    /// the same pair, picked from the destination state by
    /// `SurfaceStyleBody.fadeAnimation` (open when expanding, close otherwise) —
    /// and that fade is the one animation
    /// Reduce Motion does NOT suppress: a cross-fade IS what the preference asks
    /// for in place of motion, so gating it would swap the fade for a
    /// single-frame pop, the thing the preference exists to avoid.
    static let open: Animation = .spring(response: openResponse, dampingFraction: openDamping)
    static let close: Animation = .spring(response: closeResponse, dampingFraction: closeDamping)

    /// Provenance-aware animation for the surface's GEOMETRY (frame + corner
    /// radius) — never its opacity. The motion contract: transitions between two
    /// visible layouts morph (compact↔expanded, now-playing↔HUD) under the
    /// directional spring; an appearance from hidden or a disappearance to hidden
    /// is a fade at the FINAL frame — no geometry travel. So when either side is
    /// the hidden/empty layout this returns nil: the frame and radius SNAP to the
    /// destination while the opacity (animated separately in each view) fades. Nil
    /// on the geometry alone is why a HUD born from hidden lands at its own rule
    /// frame instead of gliding down from the last now-playing rect.
    ///
    /// Expressed over `fromEmpty`/`toEmpty` booleans rather than the shared
    /// SurfaceLayoutKind (SurfaceStyleCore): the motion gate depends on exactly
    /// two provenance facts, and taking the enum would couple it to layout
    /// vocabulary it never reads. `expanding` picks the same spring the views
    /// already pick by `isExpanded`.
    ///
    /// Reduce Motion contract (app-wide, MG5): with the preference on every
    /// geometry/content/width morph resolves to nil so layouts land dry and only
    /// the opacity fades survive (a cross-fade is the accessibility-preferred
    /// substitution). The leaves' own value animations ask `respecting` below,
    /// and the perpetual animations (the waveform, the title marquee) ask
    /// `allowsPerpetualMotion`.
    static func geometryAnimation(fromEmpty: Bool, toEmpty: Bool, expanding: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        guard !fromEmpty, !toEmpty else { return nil }
        return expanding ? open : close
    }

    /// Provenance-aware animation for the content crossfade — the scope closest
    /// to the surface's branches, which also governs the bounds the material,
    /// clips and stroke are sized off (a `.background`/clip sized to the node
    /// below the modifier). It must therefore SNAP that geometry on an
    /// APPEARANCE from hidden: with a spring here the material springs from the
    /// invisible compact/empty rect to the destination and draws OUTSIDE the
    /// snapped outer frame — a ghost that grows and shrinks behind the
    /// HUD (the fixed window is larger than every state, so there is room to
    /// show it). On appearance the surface is invisible anyway (opacity 0, faded
    /// in separately), so the branch swap needs no motion — nil.
    ///
    /// On a DISAPPEARANCE it stays the directional spring so the outgoing glyph
    /// FADES with the surface instead of popping out a frame before the opacity
    /// fade catches up; the disappearance geometry does not travel because the
    /// hidden layout freezes the outgoing rect (each view's effective-layout
    /// geometry), so a non-nil spring here has no size delta to animate. Between
    /// visible layouts it is the same crossfade+morph as the geometry spring.
    static func contentAnimation(fromEmpty: Bool, expanding: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return fromEmpty ? nil : (expanding ? open : close)
    }

    /// A plain visible→visible morph under the open spring (the view-only band
    /// resize, the card's width hug) — no provenance branch, but the same Reduce
    /// Motion gate as the geometry/content springs: nil under the preference so
    /// the resize lands dry while its opacity/content still fades.
    ///
    /// Directionless ON PURPOSE, and the cost of that is quantified rather than
    /// forbidden: the open spring's damping is deliberately under critical
    /// (`openDamping` 0.8), so a return trip overshoots by roughly 1.5% of its
    /// delta. Its clients here swing on the order of a hundred points — the
    /// view-only band resize, the card's width hug — which puts the bounce under
    /// 2 pt, and that is the shipped behaviour: at that size it reads as the
    /// surface settling, not as a wobble.
    ///
    /// The warning is about SCALE, then, not about round trips as such. A large
    /// geometry morph that goes one way and comes back the other wants a spring
    /// chosen by the destination, because there the same 1.5% is a visible bounce
    /// against the menu bar — the destination picks the spring, which is what
    /// `geometryAnimation` does from provenance.
    static func morph(reduceMotion: Bool) -> Animation? {
        respecting(reduceMotion: reduceMotion, open)
    }

    /// The Reduce Motion substitution for a value animation, made once for every
    /// leaf (the level glide, the knob reveal, the tone fade, the symbol replace):
    /// under the preference the value lands dry, nil being `.animation`'s and
    /// `withAnimation`'s own "no animation". Each component keeps its own timing;
    /// only this decision lives here.
    static func respecting(reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Whether a perpetual animation may run: both vetoes, because Low Power is
    /// the system asking that nothing be spent on movement, and a loop over the
    /// menu bar is exactly that spend (docs/STATE-FLOW.md).
    static func allowsPerpetualMotion(reduceMotion: Bool, lowPower: Bool) -> Bool {
        !reduceMotion && !lowPower
    }

    /// HUD level-indicator spring (HUDLevelSlider): a fast glide with a barely
    /// perceptible settle, the native volume/brightness feel. The response is
    /// short so a single keypress lands well before the ~1.5 s HUD revert, yet
    /// long enough to read as a glide instead of a jump; the damping sits just
    /// under critical, so the overshoot is under one percent — near-invisible on
    /// purpose (drop it toward ~0.8 if the settle should read livelier; below
    /// that it visibly wobbles). Scoped to the level
    /// value only, never the surface morph. Named apart from open/close so the
    /// author can tune it on hardware without perturbing the surface springs.
    private static let hudLevelResponse: Double = 0.28
    private static let hudLevelDamping: Double = 0.86
    static let hudLevel: Animation = .spring(response: hudLevelResponse, dampingFraction: hudLevelDamping)

    /// The bar's answer to a held key (docs/DECISIONS.md: the-bar-answers-the-press):
    /// UIKit's own springs for the volume buttons, `update` while the key is down
    /// and `settle` once it is up, both critically damped (UIKitCore, iOS 26.1,
    /// `_UIFluidSliderDiscreteButtonDriverSettings`, read decompiled). A key press
    /// carries no momentum to reward: Apple keeps overshoot for gestures that do
    /// (WWDC18 "Designing Fluid Interfaces", session 803).
    ///
    /// The drag's growth rides `hudLevel` on purpose: it lands in the same
    /// transaction as the drag's first level change, and one transaction carries
    /// one animation. A press shares none: it engages nothing, and the reading it
    /// causes arrives in a transaction of its own (`Coordinator.hudKeyPressed`).
    static let hudPress: Animation = .spring(response: 0.3, dampingFraction: 1.0)
    static let hudPressSettle: Animation = .spring(response: 0.6, dampingFraction: 1.0)
    /// The drag's growth settling thin.
    static let hudSettle: Animation = .spring(response: 0.45, dampingFraction: 1.0)

    /// The press or its settle, by where the bar is going.
    static func hudPress(pressed: Bool) -> Animation {
        pressed ? hudPress : hudPressSettle
    }

    /// The growth or the settle, by where the bar is going.
    static func hudEngage(engaged: Bool) -> Animation {
        engaged ? hudLevel : hudSettle
    }

    /// Whether the bar answers a press at all. Reduce Motion turns both off: the
    /// system's own glass "disables any elastic properties" under it (Apple,
    /// WWDC25 "Meet Liquid Glass", session 219), and a bar that grows and shrinks
    /// on every press is the same motion by another name. The level's glide is
    /// gated on its own (`HUDLevelSlider.levelAnimation`).
    static func allowsHUDPressMotion(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    /// Headroom the fixed window keeps past the expanded frame (sideways and away
    /// from the anchored edge, which stays pinned): the open spring's overshoot carries
    /// the surface a few points past its target, and without headroom the
    /// window edge would crop the peak.
    static let overshootHeadroom: CGFloat = 12
}
