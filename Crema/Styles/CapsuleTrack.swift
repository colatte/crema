import SwiftUI

/// The bar this app draws for a 0…1 value: a 4 pt capsule with a white fill and
/// a knob that appears only under the pointer.
///
/// It lives here because two surfaces draw it — the HUD level and the
/// now-playing scrubber — and one home is what keeps the two bars in one card
/// from drifting apart; the look is measured off the Tahoe banner and Control
/// Center on hardware (`docs/DECISIONS.md: hud-capsule-track`).
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
    /// The direction the bar runs: horizontal by default; `HUDPlacement.axis`
    /// names the placements where a bar stands upright.
    var axis: Axis = .horizontal

    /// Set by the Card's glass, whose body can turn pale and takes its own recess
    /// (`glassTrack`).
    @Environment(\.surfaceIsGlass) private var onGlass

    // Measured off the Tahoe banner (macOS 26.5.2): a 4 pt track with
    // semicircular caps, a subtle recess, and a 17.5×14 pt knob only under the
    // pointer. The recess is ANCHORED — a black base under a white wash — so the
    // fill/track separation holds over whatever the window's material lets
    // through, instead of riding the wallpaper's luminance. The 16 pt hit row is
    // the measured height of the stock Slider both callers replaced: the drag
    // target must not regress and no surrounding layout may move.
    nonisolated static let trackHitHeight: CGFloat = 16
    nonisolated static let trackThickness: CGFloat = 4
    static let trackBase = Color.black.opacity(0.25)
    static let trackWash = Color.white.opacity(0.15)
    /// The recess on the Card's glass, which turns pale over a pale page, where
    /// the anchored recess above cuts a dark groove (#b0 against a #d8 body).
    /// Read off the system OSD's own track with scripts/probes/native-osd-edge.swift
    /// (macOS 27.0.1, 2026-10-22): #45 over a body near #1d on a dark page, #d1
    /// under a #d8 body on a pale one. A grey of 0.74 at a quarter opacity lands
    /// on both: lighter than a dark body, a shade under a pale one. The player's
    /// glass is dimmed (`SurfaceChrome.glassDimming`), a dark body on any page,
    /// where the same grey reads lighter than the body as the system's does.
    static let glassTrack = Color(white: 0.74).opacity(0.25)
    static let fillColor = Color.white
    /// As drawn on a horizontal bar; an upright bar draws it transposed, so its
    /// long side always lies along the track.
    nonisolated static let knobSize = CGSize(width: 17.5, height: 14)
    static let knobColor = Color(white: 0.91)

    /// Component-private affordance timing, so it lives here rather than in
    /// `SurfaceAnimation` (which keeps the values that participate in the
    /// presentation contracts). Under Reduce Motion the knob snaps.
    static let knobRevealDuration: Double = 0.15

    static func knobReveal(reduceMotion: Bool) -> Animation? {
        SurfaceAnimation.respecting(reduceMotion: reduceMotion, .easeOut(duration: knobRevealDuration))
    }

    /// Where the bar STARTS — the end its fill grows from and its zero sits at —
    /// against the POINTER's coordinates, which SwiftUI reports from the left
    /// edge in either language, x growing rightward and y downward. A horizontal
    /// bar starts at the leading edge, the far end of x under right-to-left. An
    /// upright bar starts at the BOTTOM, the far end of y, in every language: a
    /// level rises, it is not read. Measured with a window under each direction
    /// (macOS 27.0.1, 2026-10-22): a press 20 pt from the left edge reads x = 20
    /// in both. What is DRAWN at a coordinate follows `drawnReversed` instead.
    nonisolated static func runsReversed(axis: Axis, layoutDirection: LayoutDirection) -> Bool {
        axis == .vertical || layoutDirection == .rightToLeft
    }

    /// The same start against the coordinates a view is DRAWN at (`position`,
    /// `offset`), which SwiftUI lays out from the leading edge in either language
    /// (measured with ImageRenderer, macOS 27.0.1, 2026-10-22: both mirror under
    /// right-to-left) and from the top. So only an upright bar runs reversed here.
    /// Reading `runsReversed` for a drawing flips it twice under right-to-left.
    nonisolated static func drawnReversed(axis: Axis) -> Bool {
        axis == .vertical
    }

    /// The same start, as layout: the alignment the fill grows from. `.leading`
    /// flips under right-to-left on its own, so only the axis decides here; the
    /// pointer half of the question is `runsReversed`. Every body drawn from a
    /// start reads it — the capsule, the filled bar, the glyph riding inside
    /// it — so fill and drag cannot part.
    nonisolated static func startAlignment(axis: Axis) -> Alignment {
        axis == .horizontal ? .leading : .bottom
    }

    /// The start as an edge, for an inset measured from it.
    nonisolated static func startEdge(axis: Axis) -> Edge.Set {
        axis == .horizontal ? .leading : .bottom
    }

    /// A size read along the bar: the x-or-y choice made once, for every length
    /// and every pointer coordinate the bar uses.
    nonisolated static func length(of size: CGSize, axis: Axis) -> CGFloat {
        axis == .horizontal ? size.width : size.height
    }

    /// A pointer read along the bar.
    nonisolated static func coordinate(of point: CGPoint, axis: Axis) -> CGFloat {
        axis == .horizontal ? point.x : point.y
    }

    /// The point at `along` on the bar, centred across it.
    nonisolated static func point(along: CGFloat, centeredIn size: CGSize, axis: Axis) -> CGPoint {
        axis == .horizontal
            ? CGPoint(x: along, y: size.height / 2)
            : CGPoint(x: size.width / 2, y: along)
    }

    /// The knob as drawn on this axis: its long side along the track.
    nonisolated static func knobFrame(axis: Axis) -> CGSize {
        axis == .horizontal ? knobSize : CGSize(width: knobSize.height, height: knobSize.width)
    }

    nonisolated static func fillLength(for value: Double, trackLength: CGFloat) -> CGFloat {
        max(0, min(value, 1)) * trackLength
    }

    /// The curved fill's length: the proportional length floored at the track
    /// thickness, so the smallest visible fill is a circle-capped nub — a fill
    /// shorter than it is thick would draw as a squashed oval across the track.
    /// Exactly zero stays empty: 0% shows the bare track, never a phantom dot.
    nonisolated static func capsuleFillLength(for value: Double, trackLength: CGFloat) -> CGFloat {
        let fill = fillLength(for: value, trackLength: trackLength)
        guard fill > 0 else { return 0 }
        return max(fill, trackThickness)
    }

    /// The knob travels the inset track [halfKnob, length − halfKnob] linearly
    /// with the value — the native thumb mapping on the OUTPUT side only. The
    /// pointer→value mapping (`fraction`) deliberately stays over the FULL
    /// length, so tap-to-set still reaches 0/1 at the row's very ends and the
    /// fill boundary (not the knob centre) is what follows the finger; do not
    /// inset it to match. The knob never exits the row and never stops
    /// responding: a boundary clamp instead freezes it for the last ~halfKnob of
    /// travel at each extreme while the fill keeps following the pointer — the
    /// jam seen on hardware at 0 and 100%. The coordinate is along the bar, in the
    /// space the knob is drawn in (`drawnReversed`).
    nonisolated static func knobCenter(for value: Double, trackLength: CGFloat, reversed: Bool) -> CGFloat {
        let halfKnob = knobSize.width / 2
        let travel = max(trackLength - knobSize.width, 0)
        let offset = halfKnob + CGFloat(min(max(value, 0), 1)) * travel
        return reversed ? trackLength - offset : offset
    }

    /// Pointer → 0…1, over the FULL length (see `knobCenter` for why it is not
    /// inset). The coordinate is the pointer's along the bar, in the view's own
    /// space, which does not flip with the layout — the fill's start does — so a
    /// reversed bar mirrors it and the drag follows the fill. Every bar drawn on
    /// this track maps its pointer here: the HUD level and the scrubber. Nil on
    /// a degenerate length.
    nonisolated static func fraction(at coordinate: CGFloat, trackLength: CGFloat, reversed: Bool) -> Double? {
        guard trackLength > 0 else { return nil }
        let fraction = min(max(Double(coordinate / trackLength), 0), 1)
        return reversed ? 1 - fraction : fraction
    }

    var body: some View {
        GeometryReader { geometry in
            let length = Self.length(of: geometry.size, axis: axis)
            // The fill's end is CURVED — a deliberate deviation from the
            // measured native flat cut, the iOS Music/players language the
            // author prefers (hud-capsule-track). Its starting cap coincides
            // with the track's own, so only the far end reads differently; a
            // spring overshoot is cropped by the clip because the stack is
            // length-pinned (a bare ZStack would report the union of its children
            // and grow with the oversized animated fill instead of cropping it).
            ZStack(alignment: Self.startAlignment(axis: axis)) {
                if onGlass {
                    Capsule().fill(Self.glassTrack)
                } else {
                    Capsule().fill(Self.trackBase)
                    Capsule().fill(Self.trackWash)
                }
                Capsule()
                    .fill(Self.fillColor)
                    .frame(along: axis, Self.capsuleFillLength(for: value, trackLength: length))
            }
            .frame(along: axis, length)
            .clipShape(Capsule())
            .frame(across: axis, Self.trackThickness)
            .frame(maxWidth: axis == .vertical ? .infinity : nil, maxHeight: axis == .horizontal ? .infinity : nil)
            .overlay {
                Capsule()
                    .fill(Self.knobColor)
                    // Light from above in both orientations: the shadow is not
                    // turned with the bar.
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    .frame(width: Self.knobFrame(axis: axis).width, height: Self.knobFrame(axis: axis).height)
                    .position(knobPosition(in: geometry.size, length: length))
                    .opacity(showsKnob ? 1 : 0)
                    .animation(Self.knobReveal(reduceMotion: reduceMotion), value: showsKnob)
                    .allowsHitTesting(false)
            }
        }
    }

    private func knobPosition(in size: CGSize, length: CGFloat) -> CGPoint {
        let along = Self.knobCenter(
            for: value,
            trackLength: length,
            reversed: Self.drawnReversed(axis: axis)
        )
        return Self.point(along: along, centeredIn: size, axis: axis)
    }
}

extension View {
    /// A frame on the bar's own axis: the length along it, the other side free.
    func frame(along axis: Axis, _ length: CGFloat) -> some View {
        frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil)
    }

    /// A frame across the bar's axis: its thickness, the length free. Nil leaves
    /// both free — a bar that fills whatever its host proposes.
    func frame(across axis: Axis, _ thickness: CGFloat?) -> some View {
        frame(width: axis == .vertical ? thickness : nil, height: axis == .horizontal ? thickness : nil)
    }
}
