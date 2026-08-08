import SwiftUI

/// The bar this app draws for a 0…1 value: a 4 pt capsule with a white fill and
/// a knob that appears only under the pointer.
///
/// It lives here because two surfaces draw it and they had drifted. The HUD
/// level owned this look — measured off the Tahoe banner and Control Center on
/// hardware, recorded in `docs/DECISIONS.md: hud-capsule-track` — while the
/// now-playing scrubber kept a stock `Slider`: a thumb always visible, tinted
/// with the artwork accent. Two bars in the same card obeying opposite rules,
/// one of them with a written decision behind it. Reported from the lock screen,
/// where they sit two rows apart.
///
/// What is shared is the DRAWING and the numbers behind it. Each caller keeps
/// its own gesture, because the two mean different things: the HUD writes a
/// level continuously, the scrubber holds a draft and seeks once on release.
struct CapsuleTrack: View {
    /// Clamped 0…1. Out-of-range is the caller's arithmetic showing, and it
    /// draws as the nearest end rather than escaping the clip.
    let value: Double
    /// The affordance-on-demand: no knob at rest, one fading in under the
    /// pointer. The caller decides what "under the pointer" means — the whole
    /// surface for a HUD (hover holds it open), the row itself for a scrubber.
    let showsKnob: Bool
    var reduceMotion: Bool = false
    var layoutDirection: LayoutDirection = .leftToRight

    // Measured off the Tahoe banner (macOS 26.5.2): a 4 pt track with
    // semicircular caps, a subtle recess, and a 17.5×14 pt knob only under the
    // pointer. The recess is ANCHORED — a black base under a white wash — so the
    // fill/track separation holds over whatever the window's material lets
    // through, instead of riding the wallpaper's luminance. The 16 pt hit row is
    // the measured height of the stock Slider both callers replaced: the drag
    // target must not regress and no surrounding layout may move.
    static let trackHitHeight: CGFloat = 16
    static let trackThickness: CGFloat = 4
    static let trackBase = Color.black.opacity(0.25)
    static let trackWash = Color.white.opacity(0.15)
    static let fillColor = Color.white
    static let knobSize = CGSize(width: 17.5, height: 14)
    static let knobColor = Color(white: 0.91)

    /// Component-private affordance timing, so it lives here rather than in
    /// `SurfaceAnimation` (which keeps the values that participate in the
    /// presentation contracts). Under Reduce Motion the knob snaps.
    static let knobRevealDuration: Double = 0.15

    static func knobReveal(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: knobRevealDuration)
    }

    static func fillWidth(for value: Double, trackWidth: CGFloat) -> CGFloat {
        max(0, min(value, 1)) * trackWidth
    }

    /// The curved fill's width: the proportional width floored at the track
    /// thickness, so the smallest visible fill is a circle-capped nub — a fill
    /// narrower than it is tall would draw as a squashed vertical oval. Exactly
    /// zero stays empty: 0% shows the bare track, never a phantom dot.
    static func capsuleFillWidth(for value: Double, trackWidth: CGFloat) -> CGFloat {
        let fill = fillWidth(for: value, trackWidth: trackWidth)
        guard fill > 0 else { return 0 }
        return max(fill, trackThickness)
    }

    /// The knob travels the inset track [halfKnob, width − halfKnob] linearly
    /// with the value — the native thumb mapping on the OUTPUT side only. The
    /// pointer→value mapping deliberately stays over the FULL width, so
    /// tap-to-set still reaches 0/1 at the row's very ends and the fill boundary
    /// (not the knob centre) is what follows the finger; do not inset it to
    /// match. The knob never exits the row and never stops responding: an
    /// earlier boundary-clamp mapping froze it for the last ~halfKnob of travel
    /// at each extreme while the fill kept following the pointer — the visual
    /// jam reported from hardware at 0 and 100%.
    static func knobCenterX(
        for value: Double, trackWidth: CGFloat, layoutDirection: LayoutDirection
    ) -> CGFloat {
        let halfKnob = knobSize.width / 2
        let travel = max(trackWidth - knobSize.width, 0)
        let x = halfKnob + CGFloat(min(max(value, 0), 1)) * travel
        return layoutDirection == .rightToLeft ? trackWidth - x : x
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            // The fill's end is CURVED — a deliberate deviation from the
            // measured native flat cut, the iOS Music/players language the
            // author prefers (hud-capsule-track). Its leading cap coincides with
            // the track's own, so only the trailing end reads differently; a
            // spring overshoot is cropped by the clip because the stack is
            // width-pinned (a bare ZStack would report the union of its children
            // and grow with the oversized animated fill instead of cropping it).
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
                Capsule()
                    .fill(Self.knobColor)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: Self.knobSize.width, height: Self.knobSize.height)
                    .position(
                        x: Self.knobCenterX(
                            for: value, trackWidth: width, layoutDirection: layoutDirection
                        ),
                        y: geometry.size.height / 2
                    )
                    .opacity(showsKnob ? 1 : 0)
                    .animation(Self.knobReveal(reduceMotion: reduceMotion), value: showsKnob)
                    .allowsHitTesting(false)
            }
        }
    }
}
