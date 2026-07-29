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
/// The `appearance` picks the body; the mechanics — drag anywhere on the row,
/// tap-to-set, the RTL mirror, the spring with its drag suspension and Reduce
/// Motion gate, the kind-snap, accessibility — live once, shared by all three:
/// - `.capsule` — the default every skin gets: the Tahoe banner's bar, drawn by
///   us. Owning the drawing is the point — Crema replaces the system's HUD, so
///   it tracks the system's HUD look (thumbless 4 pt capsule), not the system's
///   control, whose stock thumb was the misalignment being replaced. One
///   deliberate deviation: the fill's end is CURVED (a capsule, the iOS
///   Music/players language), not the native flat cut (docs/DECISIONS.md:
///   hud-capsule-track). A knob fades in under the pointer, the measured
///   Control Center affordance-on-demand.
/// - `.segmented` — the Classic bezel's 16-segment bar filled by width
///   (design-reference §4.4): Classic is deliberate pre-Tahoe nostalgia, so it
///   keeps the bezel's own indicator and shows no hover knob.
/// - `.filled` — the iOS-style full-bleed bar the Card can opt into: the whole
///   proposed frame is the indicator; the card's own clip rounds it. Its
///   remainder darkens where the capsule's track recesses — opposite polarities
///   because they cite different references (the recessed Tahoe track vs the
///   full-bleed iOS bar), both deliberate.
struct HUDLevelSlider: View {
    /// The three bodies. Card maps its persisted HUDIndicatorStyle here
    /// (.slider → .capsule, .filled → .filled); Notch takes the default and
    /// Classic passes .segmented — the persisted enum stays a Card-only choice.
    enum Appearance: Equatable {
        case capsule
        case segmented
        case filled
    }

    let kind: SystemHUD.Kind
    let value: Double
    let onChange: (Double) -> Void
    var appearance: Appearance = .capsule
    /// The panel-local pointer signal (SurfaceDisplayPolicy.pointerInside)
    /// that reveals the capsule knob — per display, so only the hovered
    /// surface shows it. The default keeps call sites without hover knob-free.
    var isHovered: Bool = false

    /// True while the user is dragging: the spring is suspended so the fill
    /// (and knob) track the finger 1:1 rather than rubber-banding behind it.
    /// Purely visual-ephemeral state, which CLAUDE.md permits in @State.
    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    // The capsule cites the live-measured Tahoe banner (macOS 26.5.2): 4 pt
    // track with semicircular caps, a subtle recess, and a 17.5×14 pt knob
    // only under the pointer. The banner's fill ends flat — Crema's
    // deliberately does not (see capsule() and docs/DECISIONS.md:
    // hud-capsule-track). The 16 pt hit row is the measured height of the
    // stock Slider this body replaced — the drag target must not regress and
    // no surrounding layout may move.
    static let trackHitHeight: CGFloat = 16
    static let trackThickness: CGFloat = 4
    // The recess is anchored — a black base under the white wash — so the
    // fill/track separation holds over whatever the behind-window material lets
    // through, instead of riding the wallpaper's luminance.
    private static let trackBase = Color.black.opacity(0.25)
    private static let trackWash = Color.white.opacity(0.15)
    private static let fillColor = Color.white
    private static let knobSize = CGSize(width: 17.5, height: 14)
    private static let knobColor = Color(white: 0.91)

    // The Classic bezel's segments (design-reference §4.4): 16 with 2 pt gaps;
    // filled ~70% white, empty ~20%. 7.5×7.5 squares — §4.4 records the
    // original's wider-than-tall segments; squares are the recreation's metric
    // and read better at this scale. The 150 pt run fits Classic's 152 pt
    // inner budget with 2 pt slack (pinned by test).
    private static let segmentCount = 16
    private static let segmentSide: CGFloat = 7.5
    private static let segmentSpacing: CGFloat = 2
    private static let segmentCorner: CGFloat = 1.5
    private static let segmentFilled = Color.white.opacity(0.7)
    private static let segmentEmpty = Color.white.opacity(0.2)

    var body: some View {
        indicator
            // Scoped to the level only. A key-press burst just rewrites `value`
            // from above (the drag closures fire only on drag, so there is no
            // echo to queue); each new value retargets the in-flight spring with
            // its velocity preserved, so the fill chases the newest level without
            // stacking. The spring is off while dragging (it follows the finger)
            // and under Reduce Motion (the value jumps as it did before).
                .animation(
                    Self.animatesLevel(isEditing: isEditing, reduceMotion: reduceMotion) ? SurfaceAnimation.hudLevel : nil,
                    value: value
                )
                // Identity keyed on the kind: volume→brightness swaps to an unrelated
                // 0…1 scale, so the level snaps there instead of gliding through
                // meaningless in-between positions (the glide is for changes within one
                // kind).
                .id(kind)
                // The identity flip does NOT reset `isEditing` — the @State lives
                // on this view, above the `.id` — so a kind flip mid-drag (its
                // gesture torn down, onEnded never firing) would strand the
                // spring suspended without this explicit clear.
                .onChange(of: kind) { _, _ in isEditing = false }
                // One accessibility element, shared by the three bodies: a Slider
                // representation keeps the slider role and its adjustability, which
                // the hand-drawn bodies do not carry. VoiceOver behavior is part of
                // the hardware acceptance session.
                .accessibilityRepresentation {
                    Slider(value: Binding(get: { value }, set: onChange), in: 0...1)
                }
                .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var indicator: some View {
        GeometryReader { geometry in
            visual(width: geometry.size.width, height: geometry.size.height)
                // The whole row is the hit target: a drag anywhere sets the
                // level, and a tap (minimumDistance 0) sets it at the touch
                // point — the same reach the stock slider gave via its track.
                    .contentShape(Rectangle())
                    .gesture(drag(width: geometry.size.width))
        }
        // The filled bar fills whatever the card proposes; the other bodies
        // take the fixed hit row so their thin visuals keep a full-size target.
        .frame(height: appearance == .filled ? nil : Self.trackHitHeight)
    }

    @ViewBuilder private func visual(width: CGFloat, height: CGFloat) -> some View {
        switch appearance {
        case .capsule:
            capsule(width: width, height: height)
        case .segmented:
            segments
        case .filled:
            filledBar(width: width)
        }
    }

    /// The fill is a leading capsule: its end is CURVED — a deliberate
    /// deviation from the measured native flat cut, the iOS Music/players
    /// language the author prefers (docs/DECISIONS.md: hud-capsule-track).
    /// Its leading cap coincides with the track's own leading cap (same
    /// radius, same anchor), so only the trailing end reads differently; a
    /// spring overshoot is cropped by the clip because the stack is
    /// width-pinned below (a bare ZStack would report the union of its
    /// children and grow with the oversized animated fill instead of
    /// cropping it). The width floor (capsuleFillWidth) keeps a low value a
    /// round nub, never a squashed vertical oval.
    private func capsule(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Self.trackBase)
            Capsule().fill(Self.trackWash)
            Capsule()
                .fill(Self.fillColor)
                .frame(width: Self.capsuleFillWidth(for: value, trackWidth: width))
        }
        .frame(width: width)
        .clipShape(Capsule())
        .frame(height: Self.trackThickness)
        .frame(maxHeight: .infinity)
        .overlay {
            knob(trackWidth: width, rowHeight: height)
        }
    }

    /// The measured Control Center affordance: no knob at rest, an oval fading
    /// in under the pointer, riding the inset track with the value (the native
    /// thumb mapping — see knobCenterX). Hover holds the HUD — the pointer's
    /// arrival cancels the revert timer (Coordinator.publishPointer),
    /// introduced with the knob so its premise is real: a hovered HUD is not
    /// transient, which is exactly when a drag affordance earns its place
    /// (docs/DECISIONS.md: hud-capsule-track).
    @ViewBuilder private func knob(trackWidth: CGFloat, rowHeight: CGFloat) -> some View {
        let visible = Self.showsKnob(appearance: appearance, isHovered: isHovered, isEditing: isEditing)
        Capsule()
            .fill(Self.knobColor)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
            .frame(width: Self.knobSize.width, height: Self.knobSize.height)
            .position(
                x: Self.knobCenterX(for: value, trackWidth: trackWidth, layoutDirection: layoutDirection),
                y: rowHeight / 2
            )
            .opacity(visible ? 1 : 0)
            .animation(Self.knobReveal(reduceMotion: reduceMotion), value: visible)
            .allowsHitTesting(false)
    }

    private var segments: some View {
        HStack(spacing: Self.segmentSpacing) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Self.segmentCorner).fill(Self.segmentEmpty)
                    Rectangle()
                        .fill(Self.segmentFilled)
                        .frame(width: Self.segmentSide * Self.segmentFill(index: index, value: value))
                }
                .clipShape(RoundedRectangle(cornerRadius: Self.segmentCorner))
                .frame(width: Self.segmentSide, height: Self.segmentSide)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// iOS-style bar: the whole HUD surface is the indicator. The fill sweeps
    /// from the leading edge to `value` over a dark remainder, no thumb and no
    /// inner track — the component fills the space it is proposed (the card's
    /// HUD frame) and the card's own rounded-rect clip (vibrantSurface) rounds
    /// the sweep, so no radius or fixed height lives here. That container clip
    /// is also what clamps the fill through a spring overshoot: the animated
    /// width can drive past full and the card's right corner crops it.
    private func filledBar(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(CardMetrics.hudFilledEmpty)
            Rectangle()
                .fill(CardMetrics.hudFilledFill)
                .frame(width: Self.fillWidth(for: value, trackWidth: width))
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard let fraction = Self.fraction(
                    atX: gesture.location.x, trackWidth: width, layoutDirection: layoutDirection
                ) else { return }
                // Raised before onChange so the value coming straight back from
                // the Coordinator finds the spring already suspended.
                isEditing = true
                onChange(fraction)
            }
            .onEnded { _ in isEditing = false }
    }

    // The mechanics extracted pure (HUDLevelSliderTests); the bodies stay thin.

    /// Gesture coordinates are physical and do not flip with the layout (the
    /// leading-anchored fill does) — mirror the fraction under right-to-left so
    /// drag follows fill. Nil on a degenerate width.
    nonisolated static func fraction(atX x: CGFloat, trackWidth: CGFloat, layoutDirection: LayoutDirection) -> Double? {
        guard trackWidth > 0 else { return nil }
        let fraction = min(max(Double(x / trackWidth), 0), 1)
        return layoutDirection == .rightToLeft ? 1 - fraction : fraction
    }

    nonisolated static func fillWidth(for value: Double, trackWidth: CGFloat) -> CGFloat {
        max(0, min(value, 1)) * trackWidth
    }

    /// The curved fill's width: the proportional width floored at the track
    /// thickness, so the smallest visible fill is a circle-capped nub — a fill
    /// narrower than it is tall would draw as a squashed vertical oval. Exactly
    /// zero stays empty: 0% shows the bare track, never a phantom dot. (The
    /// spring can still interpolate through sub-floor widths on a glide out of
    /// zero — one brief frame, accepted.)
    nonisolated static func capsuleFillWidth(for value: Double, trackWidth: CGFloat) -> CGFloat {
        let fill = fillWidth(for: value, trackWidth: trackWidth)
        guard fill > 0 else { return 0 }
        return max(fill, trackThickness)
    }

    nonisolated static func animatesLevel(isEditing: Bool, reduceMotion: Bool) -> Bool {
        !isEditing && !reduceMotion
    }

    /// The knob travels the inset track [halfKnob, width − halfKnob] linearly
    /// with the value — the native thumb mapping on the OUTPUT side only: the
    /// pointer→value mapping (`fraction`) deliberately stays over the full
    /// width, so tap-to-set still reaches 0/1 at the row's very ends and the
    /// FILL boundary (not the knob center) is what follows the finger; do not
    /// inset `fraction` to match. The knob never exits the row AND never
    /// stops responding: the previous boundary-clamp mapping froze it for the
    /// last ~halfKnob of travel at each extreme while the value (and the
    /// fill) kept following the pointer — the visual jam reported from
    /// hardware at 0/100%. The fill boundary never escapes the knob's body:
    /// |boundary − center| = halfKnob·|2·value − 1| — zero at mid-scale, the
    /// halfKnob bound touched exactly at 0/1 — independent of trackWidth.
    /// `.position` is physical coordinates, so it mirrors by hand like the
    /// fraction above.
    nonisolated static func knobCenterX(for value: Double, trackWidth: CGFloat, layoutDirection: LayoutDirection) -> CGFloat {
        let halfKnob = knobSize.width / 2
        let travel = max(trackWidth - knobSize.width, 0)
        let x = halfKnob + CGFloat(min(max(value, 0), 1)) * travel
        return layoutDirection == .rightToLeft ? trackWidth - x : x
    }

    /// Capsule-only, shown under the pointer or during a drag — the affordance
    /// follows the interaction, so a drag that wanders off the surface keeps
    /// its knob deliberately (not by event-mask accident). The segmented
    /// Classic and the full-bleed filled bar stay bare — their references
    /// carry no knob.
    /// The knob's reveal — an opacity fade under the pointer, the measured
    /// Control Center affordance-on-demand. A component-private affordance
    /// timing, so it lives here, not in SurfaceAnimation (which keeps the
    /// values that participate in the presentation contracts); value-scoped:
    /// it never reaches the surface morph. Under Reduce Motion the knob snaps
    /// in and out — a deliberate over-restriction (value animations suspend
    /// under RM; the opacity-fade allowance belongs to surface appear/dismiss).
    nonisolated static let knobRevealDuration: Double = 0.15
    nonisolated static func knobReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: knobRevealDuration)
    }

    nonisolated static func showsKnob(appearance: Appearance, isHovered: Bool, isEditing: Bool) -> Bool {
        appearance == .capsule && (isHovered || isEditing)
    }

    /// Card's persisted choice → body (pinned by test): .slider is the
    /// capsule, .filled the full-bleed bar.
    nonisolated static func appearance(for style: HUDIndicatorStyle) -> Appearance {
        style == .filled ? .filled : .capsule
    }

    /// How much of segment `index` is filled at `value` — by width, the
    /// boundary segment partially (design-reference §4.4).
    nonisolated static func segmentFill(index: Int, value: Double) -> Double {
        min(max(value * Double(segmentCount) - Double(index), 0), 1)
    }

    /// VoiceOver label, keyed on the HUD kind so the announced value has a
    /// subject; the muted glyph stays a visual-only cue rather than leaking
    /// volume sub-state into this shared level control.
    private var accessibilityLabel: Text {
        switch kind {
        case .volume:
            return Text("hud.accessibility.volume", comment: "VoiceOver label for the volume HUD bar")
        case .screenBrightness:
            return Text("hud.accessibility.brightness", comment: "VoiceOver label for the screen-brightness HUD bar")
        case .keyboardBrightness:
            return Text("hud.accessibility.keyboardBrightness", comment: "VoiceOver label for the keyboard-brightness HUD bar")
        }
    }
}
