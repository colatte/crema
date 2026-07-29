import SwiftUI

/// Calibratable animation values for the presentation surfaces, isolated in
/// one place (design-reference §2.2/§2.3). Every value is a starting point to
/// tune on hardware, not an absolute.
///
/// All visible motion is SwiftUI's: the view morphs a sized surface inside a
/// fixed window (see NSPanelPresentationPanel). One animator, so nothing fights.
///
/// Scope rule: values that participate in the presentation contracts live here
/// (the directional morph springs, appear/dismiss, the level glide calibrated
/// against the HUD revert); a component's private affordance timing lives in
/// the component (WaveformGlyph.freezeDuration, ArtworkAccent.toneFadeDuration,
/// HUDLevelSlider.knobReveal).
enum SurfaceAnimation {
    /// Spring parameters. Open is livelier; close is critically damped — never
    /// overshoot on close, or the bounce against the static menu bar reads as
    /// instability.
    static let openResponse: Double = 0.42
    static let openDamping: Double = 0.8
    // 0.35 from the hover round's release-latency budget (t90 279 → 217 ms);
    // damping stays 1.0 — still no overshoot against the menu bar.
    static let closeResponse: Double = 0.35
    static let closeDamping: Double = 1.0

    /// Surface morph springs, chosen by direction: the destination state selects
    /// the spring (see the views).
    static let open: Animation = .spring(response: openResponse, dampingFraction: openDamping)
    static let close: Animation = .spring(response: closeResponse, dampingFraction: closeDamping)

    /// Provenance-aware animation for the surface's GEOMETRY (frame + corner
    /// radius) — never its opacity. The motion contract: transitions between two
    /// visible layouts morph (compact↔expanded, now-playing↔HUD) under the
    /// directional spring; an appearance from hidden or a disappearance to hidden
    /// is a fade at the FINAL frame — no geometry travel. So when either side is
    /// the hidden/empty layout this returns nil: the frame and radius SNAP to the
    /// destination while the opacity (animated separately in each view) fades. Nil
    /// on the geometry alone is why a HUD born from hidden lands at 210×42 instead
    /// of gliding down from the last now-playing rect.
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
    /// substitution) — one home for the rule the leaf components (HUDLevelSlider,
    /// SymbolReplaceEffect, WaveformGlyph) already honor per-value.
    static func geometryAnimation(fromEmpty: Bool, toEmpty: Bool, expanding: Bool, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        guard !fromEmpty, !toEmpty else { return nil }
        return expanding ? open : close
    }

    /// Provenance-aware animation for the content crossfade — the scope closest
    /// to the surface's branches, which also governs the bounds the material,
    /// clips and stroke are sized off (a `.background`/clip sized to the node
    /// below the modifier). It must therefore SNAP that geometry on an
    /// APPEARANCE from hidden: with a spring here the material sprang from the
    /// invisible compact/empty rect to the destination and drew OUTSIDE the
    /// snapped outer frame — the ghost the author saw grow-and-shrink behind the
    /// HUD (the fixed window is larger than every state, so there was room to
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
    static func morph(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : open
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
    static let hudLevelResponse: Double = 0.28
    static let hudLevelDamping: Double = 0.86
    static let hudLevel: Animation = .spring(response: hudLevelResponse, dampingFraction: hudLevelDamping)

    /// Headroom the fixed window keeps past the expanded frame (sideways and
    /// down; the top anchor stays pinned): the open spring's overshoot carries
    /// the surface a few points past its target, and without headroom the
    /// window edge would crop the peak.
    static let overshootHeadroom: CGFloat = 12

    /// How long a shrinking surface's old extent stays click-interactive: the
    /// close spring's visible settle (≥ 1.5 × response). Tightening earlier
    /// would forward clicks through still-visible pixels to the window below.
    /// Held at 0.7 deliberately after close dropped to 0.35 — headroom over
    /// the floor, not a live derivation.
    static let interactiveSettle: Double = 0.7
}
