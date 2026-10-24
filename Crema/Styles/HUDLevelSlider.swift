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
/// tap-to-set, the bar's start (leading, mirrored under RTL, or the bottom of an
/// upright bar), the spring with its drag suspension and Reduce Motion gate, the
/// kind-snap, accessibility — live once, shared by all three:
/// - `.capsule` — the default every skin gets: the Tahoe banner's bar, drawn by
///   us. Owning the drawing is the point — Crema replaces the system's HUD, so
///   it tracks the system's HUD look (thumbless 4 pt capsule), not the system's
///   control, whose stock thumb is the misalignment this replaces. One
///   deliberate deviation: the fill's end is CURVED (a capsule, the iOS
///   Music/players language), not the native flat cut (docs/DECISIONS.md:
///   hud-capsule-track). A knob fades in under the pointer, the measured
///   Control Center affordance-on-demand.
/// - `.segmented` — the Classic bezel's 16-segment bar filled by
///   width: Classic is deliberate pre-Tahoe nostalgia, so it
///   keeps the bezel's own indicator and shows no hover knob. The bezel has no
///   upright form: the segmented bar runs horizontal whatever `axis` asks
///   (`runningAxis`), its row and its drag included.
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
    /// The gesture ended. Reported separately from the last value because "the
    /// hand let go" is not derivable from the values: a drag that stops on 0.4 and
    /// a drag still held at 0.4 send the same number, and only one of them may be
    /// corrected under the finger.
    let onRelease: () -> Void
    var appearance: Appearance = .capsule
    /// The panel-local pointer signal (SurfaceDisplayPolicy.pointerInside)
    /// that reveals the capsule knob — per display, so only the hovered
    /// surface shows it. The default keeps call sites without hover knob-free.
    var isHovered: Bool = false
    /// The direction the bar runs (`CapsuleTrack.axis`): horizontal by default;
    /// `HUDPlacement.axis` names the placements where a bar stands upright.
    var axis: Axis = .horizontal

    /// True while the user is dragging: the spring is suspended so the fill
    /// (and knob) track the finger 1:1 rather than rubber-banding behind it.
    /// Purely visual-ephemeral state, which docs/STATE-FLOW.md permits in @State.
    @State private var isEditing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.surfaceIsGlass) private var onGlass

    // The capsule's numbers and its drawing live in `CapsuleTrack`, shared with
    // the now-playing scrubber so the two bars in one card cannot drift again.
    // Forwarded rather than re-declared: a second copy is how they drifted.
    static var trackHitHeight: CGFloat { CapsuleTrack.trackHitHeight }
    static var trackThickness: CGFloat { CapsuleTrack.trackThickness }

    // The Classic bezel's segments, from the reverse-engineered original: 16
    // with 2 pt gaps; filled ~70% white, empty ~20%. 7.5×7.5 squares — the
    // original's segments were wider than tall; squares are the recreation's metric
    // and read better at this scale. The 150 pt run fits Classic's 152 pt
    // inner budget with 2 pt slack (pinned by test).
    private nonisolated static let segmentCount = 16
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
            // and under Reduce Motion (the value jumps).
                .animation(Self.levelAnimation(isEditing: isEditing, reduceMotion: reduceMotion), value: value)
                // Identity keyed on the kind: volume→brightness swaps to an unrelated
                // 0…1 scale, so the level snaps there instead of gliding through
                // meaningless in-between positions (the glide is for changes within one
                // kind).
                .id(kind)
                // The identity flip does NOT reset `isEditing` — the @State lives
                // on this view, above the `.id` — so a kind flip mid-drag (its
                // gesture torn down, onEnded never firing) would strand the
                // spring suspended without this explicit clear. The gesture really
                // did end, so it is reported as ended: a drag left hanging would
                // hold back a correction the next release would have to deliver.
                .onChange(of: kind) { _, _ in
                    isEditing = false
                    onRelease()
                }
                // One accessibility element, shared by the three bodies: a Slider
                // representation keeps the slider role and its adjustability, which
                // the hand-drawn bodies do not carry. VoiceOver behavior is part of
                // the hardware acceptance session.
                .accessibilityRepresentation {
                    // An assistive adjustment is a whole gesture — press and release
                    // in one step — so it reports its own end (`adjust`).
                    Slider(value: Binding(get: { value }, set: { Self.adjust(to: $0, onChange: onChange, onRelease: onRelease) }), in: 0...1)
                }
                .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder private var indicator: some View {
        GeometryReader { geometry in
            let length = CapsuleTrack.length(of: geometry.size, axis: runningAxis)
            visual(size: geometry.size, length: length)
                // The whole row is the hit target: a drag anywhere sets the
                // level, and a tap (minimumDistance 0) sets it at the touch
                // point — the same reach the stock slider gave via its track.
                    .contentShape(Rectangle())
                    .gesture(drag(length: length))
        }
        // The filled bar fills whatever the card proposes; the other bodies
        // take the fixed hit row so their thin visuals keep a full-size target.
        .frame(across: runningAxis, appearance == .filled ? nil : Self.trackHitHeight)
    }

    /// The axis this body actually runs on: the one asked, except for the
    /// segmented bar, which has no upright form.
    private var runningAxis: Axis {
        appearance == .segmented ? .horizontal : axis
    }

    /// Where this bar starts, against the view's own coordinates
    /// (`CapsuleTrack.runsReversed`).
    private var reversed: Bool {
        CapsuleTrack.runsReversed(axis: runningAxis, layoutDirection: layoutDirection)
    }

    @ViewBuilder private func visual(size: CGSize, length: CGFloat) -> some View {
        switch appearance {
        case .capsule:
            capsule(size: size)
        case .segmented:
            segments
        case .filled:
            filledBar(length: length)
        }
    }

    /// The track itself, drawn by `CapsuleTrack` — the curved fill, its floor,
    /// the overshoot crop and the knob are described there, once.
    private func capsule(size: CGSize) -> some View {
        CapsuleTrack(
            value: value,
            showsKnob: Self.showsKnob(
                appearance: appearance, isHovered: isHovered, isEditing: isEditing
            ),
            reduceMotion: reduceMotion,
            axis: runningAxis
        )
        .frame(width: size.width, height: size.height)
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
    /// from the bar's start to `value` over the remainder (`hudFilledEmpty`), no
    /// thumb and no inner track — the component fills the space it is proposed
    /// (the card's HUD frame) and the card's own rounded-rect clip rounds
    /// the sweep, so no radius or fixed thickness lives here. That container clip
    /// is also what clamps the fill through a spring overshoot: the animated
    /// length can drive past full and the card's far corners crop it.
    private func filledBar(length: CGFloat) -> some View {
        ZStack(alignment: CapsuleTrack.startAlignment(axis: runningAxis)) {
            Rectangle().fill(CardMetrics.hudFilledEmpty(colorSchemeContrast, onGlass: onGlass))
            Rectangle()
                .fill(CardMetrics.hudFilledFill(colorSchemeContrast))
                .frame(along: runningAxis, CapsuleTrack.fillLength(for: value, trackLength: length))
        }
    }

    private func drag(length: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                guard let fraction = CapsuleTrack.fraction(
                    at: CapsuleTrack.coordinate(of: gesture.location, axis: runningAxis),
                    trackLength: length,
                    reversed: reversed
                ) else { return }
                // Raised before onChange so the value coming straight back from
                // the Coordinator finds the spring already suspended.
                isEditing = true
                onChange(fraction)
            }
            .onEnded { _ in
                isEditing = false
                onRelease()
            }
    }

    // The mechanics extracted pure (HUDLevelSliderTests); the bodies stay thin.

    /// What an assistive adjustment reports: the new level, then the end of the
    /// gesture. A VoiceOver increment is a press and a release in one step — no
    /// hand stays on the bar afterwards — and the ORDER carries the contract,
    /// because `onChange` is what marks a gesture as in flight: a release sent
    /// first would be undone by the change behind it, and no release at all
    /// leaves the app holding a correction for a finger that is not there,
    /// showing a level nothing wrote until the HUD dismisses itself.
    nonisolated static func adjust(
        to value: Double,
        onChange: (Double) -> Void,
        onRelease: () -> Void
    ) {
        onChange(value)
        onRelease()
    }

    /// Off while dragging (the fill follows the finger); the Reduce Motion half is
    /// `SurfaceAnimation`'s.
    nonisolated static func levelAnimation(isEditing: Bool, reduceMotion: Bool) -> Animation? {
        isEditing ? nil : SurfaceAnimation.respecting(reduceMotion: reduceMotion, SurfaceAnimation.hudLevel)
    }

    /// Capsule-only, shown under the pointer or during a drag — the affordance
    /// follows the interaction, so a drag that wanders off the surface keeps
    /// its knob deliberately (not by event-mask accident). The segmented
    /// Classic and the full-bleed filled bar stay bare — their references
    /// carry no knob. The reveal animation lives with the drawing, in
    /// CapsuleTrack.knobReveal — a second copy here is how they drifted.
    nonisolated static func showsKnob(appearance: Appearance, isHovered: Bool, isEditing: Bool) -> Bool {
        appearance == .capsule && (isHovered || isEditing)
    }

    /// Pinned by test.
    nonisolated static func appearance(for style: HUDIndicatorStyle) -> Appearance {
        style == .filled ? .filled : .capsule
    }

    /// How much of segment `index` is filled at `value` — by width, the
    /// boundary segment partially (the pre-Tahoe bezel's own rule).
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
