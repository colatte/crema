import SwiftUI

/// Shared HUD level indicator: the slider every skin shows for volume/screen and
/// keyboard brightness. Each style wraps it in its own layout (icon placement,
/// padding, stacking); only the control itself — and its spring — lives here, the
/// same one-home sharing as ScrubberRow/TransportControls.
///
/// The level glides to a new value with a contained spring (SurfaceAnimation.hudLevel)
/// instead of jumping, for the native settle. The animation is deliberately scoped
/// to the value alone: it must never reach the surface morph, the window frame, or
/// the HUD's appear/dismiss timing (those stay keyed on layoutKind in each view).
struct HUDLevelSlider: View {
    let kind: SystemHUD.Kind
    let value: Double
    let onChange: (Double) -> Void

    /// True while the user is dragging the thumb: the spring is suspended so the
    /// thumb tracks the finger 1:1 rather than rubber-banding behind it. Purely
    /// visual-ephemeral state, which CLAUDE.md permits in @State.
    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Slider(
            value: Binding(get: { value }, set: onChange),
            onEditingChanged: { isEditing = $0 }
        )
        // Scoped to the level only. A key-press burst just rewrites `value` from
        // above (the set closure fires only on drag, so there is no echo to
        // queue); each new value retargets the in-flight spring with its velocity
        // preserved, so the thumb chases the newest level without stacking. The
        // spring is off while dragging (thumb follows the finger) and under Reduce
        // Motion (the value jumps as it did before this feature).
        .animation(animatesLevel ? SurfaceAnimation.hudLevel : nil, value: value)
            // Identity keyed on the kind: volume→brightness swaps to an unrelated
            // 0…1 scale, so the level snaps there instead of gliding through
            // meaningless in-between positions (the glide is for changes within one
            // kind).
            .id(kind)
    }

    private var animatesLevel: Bool {
        !isEditing && !reduceMotion
    }
}
