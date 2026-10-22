import SwiftUI

/// One line of text that, where it does not fit and is allowed to, scrolls
/// through its whole length: it rests at its start, slides until a trailing copy
/// arrives where it began, and rests again, its edges fading where text runs out
/// of the line. Anywhere else it is the line as laid out, truncated by its own
/// limit, so it lays out exactly as a plain one-line text does and the surfaces
/// that hug their text keep hugging it.
///
/// The player expanded, the one a user stopped to read, scrolls; the compact
/// strip that announces a track for a few seconds truncates, since a scroll there
/// would barely start before it went (docs/DECISIONS.md: a-long-title-scrolls-where-it-is-read).
struct MarqueeLine<Content: View>: View {
    /// Whether this line may scroll at all.
    let scrolls: Bool
    /// When the current run began, shared by the lines of one stack so they rest
    /// together (`TrackTextStack`).
    let start: Date
    /// The longest travel among those lines, which sets the shared rhythm: a
    /// shorter line finishes early and waits where it began.
    let cycleTravel: CGFloat
    /// Hands this line's own travel up to the stack: zero while it does not move.
    let reportTravel: (CGFloat) -> Void
    @ViewBuilder let content: () -> Content

    /// The line's full width and the width it was given, measured on screen:
    /// purely visual, as docs/STATE-FLOW.md allows @State to be.
    @State private var fullWidth: CGFloat = 0
    @State private var lineWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil off the panels (previews, the Settings tiles): no mirror, no veto.
    @Environment(\.lowPowerMode) private var lowPowerMode

    private var moves: Bool {
        MarqueeMotion.moves(
            scrolls: scrolls,
            fullWidth: fullWidth,
            lineWidth: lineWidth,
            reduceMotion: reduceMotion,
            lowPower: lowPowerMode?.isLowPower ?? false
        )
    }

    var body: some View {
        content()
            .lineLimit(1)
            // Laid out always, shown only at rest: it is what sizes the line, so
            // a line that starts or stops scrolling moves nothing around it.
            .opacity(moves ? 0 : 1)
            .accessibilityHidden(moves)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { lineWidth = $0 })
            .background {
                content()
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: { fullWidth = $0 })
            }
            .overlay(alignment: .leading) {
                if moves { running }
            }
            .onChange(of: travel, initial: true) { _, travel in reportTravel(travel) }
    }

    private var travel: CGFloat {
        moves ? fullWidth + MarqueeMotion.gap : 0
    }

    /// Two copies a gap apart sliding together, so the second one arrives where
    /// the first began and the run ends on the frame it started from.
    private var running: some View {
        TimelineView(.animation) { context in
            let offset = MarqueeMotion.offset(
                elapsed: context.date.timeIntervalSince(start),
                travel: travel,
                cycleTravel: cycleTravel
            )
            let fades = MarqueeMotion.edgeFades(offset: offset, travel: travel)
            HStack(spacing: MarqueeMotion.gap) {
                content().fixedSize()
                content().fixedSize().accessibilityHidden(true)
            }
            .offset(x: -offset)
            .frame(width: lineWidth, alignment: .leading)
            .mask {
                LinearGradient(
                    stops: MarqueeMotion.maskStops(fades: fades, lineWidth: lineWidth),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
    }
}

/// The marquee's motion, pure so it is testable without a rendered view. By
/// author taste against the iPhone's Music player, not measured
/// (docs/DECISIONS.md: a-long-title-scrolls-where-it-is-read).
enum MarqueeMotion {
    /// How long the line rests at its start before each run, long enough to read
    /// the beginning first.
    static let rest: Double = 2
    /// Reading pace along the line, in points a second.
    static let speed: CGFloat = 30
    /// Air between the end of the text and the copy following it, so the two
    /// never read as one run-on line.
    static let gap: CGFloat = 32
    /// How far into the line an edge fades where text runs past it.
    static let fade: CGFloat = 12

    /// Whether the line scrolls: allowed to, too long for its width, and under
    /// neither motion veto (`SurfaceAnimation.allowsPerpetualMotion`). Half a
    /// point of slack keeps a line that fits to the pixel from flickering into
    /// motion on rounding.
    static func moves(scrolls: Bool, fullWidth: CGFloat, lineWidth: CGFloat, reduceMotion: Bool, lowPower: Bool) -> Bool {
        scrolls && fullWidth > lineWidth + 0.5
            && SurfaceAnimation.allowsPerpetualMotion(reduceMotion: reduceMotion, lowPower: lowPower)
    }

    /// How far a line's copies have slid `elapsed` seconds into the current run:
    /// zero through the rest, then steadily up to `travel`, the distance at which
    /// the second copy sits exactly where the first began. The run lasts as long
    /// as the longest line of its stack needs (`cycleTravel`); a shorter line
    /// waits at `travel`, which draws the frame it started from, so every line
    /// rests together.
    static func offset(elapsed: Double, travel: CGFloat, cycleTravel: CGFloat) -> CGFloat {
        guard travel > 0 else { return 0 }
        let cycle = rest + Double(max(travel, cycleTravel) / speed)
        let phase = max(elapsed, 0).truncatingRemainder(dividingBy: cycle)
        return phase < rest ? 0 : min(CGFloat(phase - rest) * speed, travel)
    }

    /// How much each edge fades at `offset`. The trailing edge always does, text
    /// running past it; the leading edge only while text runs past it too, so it
    /// is crisp at rest and as the copy settles into place.
    static func edgeFades(offset: CGFloat, travel: CGFloat) -> (leading: CGFloat, trailing: CGFloat) {
        (min(fade, offset, travel - offset), fade)
    }

    /// The mask's stops across a line `lineWidth` wide: transparent at a faded
    /// edge, opaque between.
    static func maskStops(fades: (leading: CGFloat, trailing: CGFloat), lineWidth: CGFloat) -> [Gradient.Stop] {
        guard lineWidth > 0 else { return [Gradient.Stop(color: .black, location: 0)] }
        let leading = min(max(fades.leading / lineWidth, 0), 0.5)
        let trailing = min(max(fades.trailing / lineWidth, 0), 0.5)
        return [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .black, location: leading),
            Gradient.Stop(color: .black, location: 1 - trailing),
            Gradient.Stop(color: .clear, location: 1),
        ]
    }
}
