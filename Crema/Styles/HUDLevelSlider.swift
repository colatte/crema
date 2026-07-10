import SwiftUI

/// Shared HUD level indicator: the control every skin shows for volume/screen and
/// keyboard brightness. Each style wraps it in its own layout (icon placement,
/// padding, stacking); only the control itself — and its spring — lives here, the
/// same one-home sharing as ScrubberRow/TransportControls.
///
/// The level glides to a new value with a contained spring (SurfaceAnimation.hudLevel)
/// instead of jumping, for the native settle. The animation is deliberately scoped
/// to the value alone: it must never reach the surface morph, the window frame, or
/// the HUD's appear/dismiss timing (those stay keyed on layoutKind in each view).
///
/// The appearance is a `variant`: the default `.slider` is the system slider every
/// skin shows; `.filled` is the iOS-style bar (no thumb, the whole bar is the fill)
/// the Card style can opt into. Both share one home for the spring, the drag
/// suspension, the reduce-motion gate, and the kind-snap — a variant is a different
/// body, never a parallel component.
struct HUDLevelSlider: View {
    let kind: SystemHUD.Kind
    let value: Double
    let onChange: (Double) -> Void
    /// Appearance; defaults to `.slider` so Notch/Classic call sites render
    /// exactly as before and never gain the option.
    var variant: HUDIndicatorStyle = .slider

    /// True while the user is dragging: the spring is suspended so the fill
    /// (or thumb) tracks the finger 1:1 rather than rubber-banding behind it.
    /// Purely visual-ephemeral state, which CLAUDE.md permits in @State.
    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    /// VoiceOver increment/decrement step for the thumbless filled bar (the
    /// system slider ships its own).
    private static let adjustStep = 0.05

    var body: some View {
        indicator
            // Scoped to the level only. A key-press burst just rewrites `value`
            // from above (the drag closures fire only on drag, so there is no
            // echo to queue); each new value retargets the in-flight spring with
            // its velocity preserved, so the fill chases the newest level without
            // stacking. The spring is off while dragging (it follows the finger)
            // and under Reduce Motion (the value jumps as it did before).
                .animation(animatesLevel ? SurfaceAnimation.hudLevel : nil, value: value)
                // Identity keyed on the kind: volume→brightness swaps to an unrelated
                // 0…1 scale, so the level snaps there instead of gliding through
                // meaningless in-between positions (the glide is for changes within one
                // kind).
                .id(kind)
    }

    @ViewBuilder private var indicator: some View {
        switch variant {
        case .slider:
            Slider(
                value: Binding(get: { value }, set: onChange),
                onEditingChanged: { isEditing = $0 }
            )
        case .filled:
            filledBar
        }
    }

    /// iOS-style bar: the whole HUD surface is the indicator. The fill sweeps
    /// from the leading edge to `value` over a dark remainder, no thumb and no
    /// inner track — the component fills the space it is proposed (the card's
    /// HUD frame) and the card's own rounded-rect clip (vibrantSurface) rounds
    /// the sweep, so no radius or fixed height lives here. That container clip
    /// is also what clamps the fill through a spring overshoot: the animated
    /// width can drive past full and the card's right corner crops it.
    private var filledBar: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Rectangle().fill(CardMetrics.hudFilledEmpty)
                Rectangle()
                    .fill(CardMetrics.hudFilledFill)
                    .frame(width: max(0, min(value, 1)) * width)
            }
            // The whole bar is the hit target: a drag anywhere sets the level,
            // and a tap (minimumDistance 0) sets it at the touch point — the same
            // reach the system slider gives via its track.
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard width > 0 else { return }
                        isEditing = true
                        // Gesture coordinates are physical and do not flip with
                        // the layout (the fill's leading anchor does) — mirror
                        // the fraction under right-to-left so drag follows fill.
                        let fraction = min(max(drag.location.x / width, 0), 1)
                        onChange(layoutDirection == .rightToLeft ? 1 - fraction : fraction)
                    }
                    .onEnded { _ in isEditing = false }
            )
        }
        .accessibilityElement()
        .accessibilityValue(Text(value.formatted(.percent)))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + Self.adjustStep, 1))
            case .decrement: onChange(max(value - Self.adjustStep, 0))
            @unknown default: break
            }
        }
    }

    private var animatesLevel: Bool {
        !isEditing && !reduceMotion
    }
}
