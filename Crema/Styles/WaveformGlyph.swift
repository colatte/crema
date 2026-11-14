import SwiftUI

/// Playback indicator: thin center-anchored bars pulsing symmetrically between
/// rest and peak, each offset a fraction of a stroke from its neighbor — one rises
/// while another falls, the live-equalizer read. (Bottom-anchored bars read as a
/// column chart; synchronized ones as a blinking block.) Drawn from playback state
/// and the clock alone — no audio capture, no spectrum analysis. The family shares
/// one tuning (`Configuration.standard`); a skin passes its own Configuration only
/// when it actually diverges.
///
/// PULSE and FORM are two questions with two rules: `dances` decides whether the
/// bars move, `stillHeights` decides what they look like when they do not. The
/// glyph is decorative only where something else says "playing" — on the compact
/// surfaces it is the sole signal, which is why a motion veto silences the
/// movement without silencing the silhouette.
struct WaveformGlyph: View {
    struct Configuration {
        var barCount: Int
        var barWidth: CGFloat
        var barSpacing: CGFloat
        var barCornerRadius: CGFloat
        var restHeight: CGFloat
        var peakHeight: CGFloat
        /// One stroke, rest to peak or peak to rest; a full cycle is two.
        var pulsePeriod: Double

        /// The family's shared tuning, which every skin uses. Override per
        /// call site only on real divergence, so one hardware calibration can
        /// never silently fork identical copies across the skins.
        static let standard = Self(
            barCount: 4,
            barWidth: 2,
            barSpacing: 2.5,
            barCornerRadius: 1,
            restHeight: 4,
            peakHeight: 12,
            pulsePeriod: 0.5
        )
    }

    let animating: Bool
    var config: Configuration = .standard

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil off the panels (previews, the Settings tiles): no mirror, no veto.
    @Environment(\.lowPowerMode) private var lowPowerMode
    @Environment(\.surfaceIsShown) private var shown
    @Environment(\.artworkAccent) private var accent
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Settle time when the pulse stops or starts: quick enough to read as an
    /// immediate freeze, slow enough not to snap. Not part of Configuration —
    /// the reaction should feel identical everywhere, even for a skin that
    /// overrides the pulse itself.
    private static let freezeDuration: Double = 0.25

    var body: some View {
        // Every input of the pulse in one value, read inside the body, so either
        // veto stops it the moment it flips and not at the next transport event.
        let dancing = Self.dances(animating: animating, reduceMotion: reduceMotion, lowPower: lowPower, shown: shown)
        let still = Self.stillHeights(
            animating: animating, reduceMotion: reduceMotion, lowPower: lowPower, shown: shown, config: config
        )
        // The pulse is sampled from the clock on every frame, never left to an
        // implicit `repeatForever`, whose life belongs to the transactions passing
        // through it (docs/DECISIONS.md: perpetual-motion-is-sampled). Paused, the
        // timeline draws nothing new.
        TimelineView(.animation(paused: !dancing)) { context in
            HStack(alignment: .center, spacing: config.barSpacing) {
                ForEach(0..<config.barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: config.barCornerRadius, style: .continuous)
                        .frame(
                            width: config.barWidth,
                            height: dancing
                                ? Self.pulseHeight(bar: index, at: context.date.timeIntervalSinceReferenceDate, config: config)
                                : still[index]
                        )
                }
            }
        }
        .frame(height: config.peakHeight)
        // The one animated change: starting or stopping, a settle between the pulse
        // and the form the bars hold still — flat at rest when playback stopped,
        // the frozen equalizer when a veto stopped the movement and playback did not.
        .animation(
            SurfaceAnimation.respecting(reduceMotion: reduceMotion, .easeOut(duration: Self.freezeDuration)),
            value: dancing
        )
        // The skin moves this glyph under springs of its own (the Card's width
        // morphs on every track change, carrying the glyph on its trailing edge).
        // A geometry group resolves that move once, for the glyph as a whole, so
        // the bars' frames stay the clock's (View.geometryGroup(), macOS 14;
        // docs/DECISIONS.md: perpetual-motion-is-sampled).
        .geometryGroup()
        // The bars take the cover's tone, styled here so all skins tint
        // identically and lifted as far as the contrast setting's background
        // needs (`ArtworkAccent.Tone.displayComponents`). No usable tone ⇒ the
        // neutral secondary.
        .foregroundStyle(
            accent.map { AnyShapeStyle($0.color(contrast: colorSchemeContrast)) } ?? AnyShapeStyle(.secondary)
        )
    }

    private var lowPower: Bool { lowPowerMode?.isLowPower ?? false }

    /// The rule itself, pure and static so it is testable without a rendered view.
    /// Two vetoes, neither reducible to the other: Reduce Motion is the user's
    /// standing request that nothing move, and Low Power Mode is the system's
    /// request that nothing be spent on motion — a perpetual pulse on a surface
    /// that sits over the menu bar is exactly what it means. An absent mirror
    /// means nobody wired one, which is no veto. A hidden surface stops it as a
    /// veto does (`surfaceIsShown`): it still draws the glyph it faded out with,
    /// and keeps the silhouette it faded out on.
    ///
    /// It decides the PULSE and nothing else; the silhouette is `stillHeights`.
    static func dances(animating: Bool, reduceMotion: Bool, lowPower: Bool, shown: Bool = true) -> Bool {
        animating && shown && SurfaceAnimation.allowsPerpetualMotion(reduceMotion: reduceMotion, lowPower: lowPower)
    }

    /// A bar's height while the pulse runs, at `time` seconds on a steady clock: a
    /// raised cosine between rest and peak, one stroke per `pulsePeriod`, each bar
    /// a `barCount`-th of a stroke behind the one before it. A pure function of
    /// the clock, so a late or skipped frame costs nothing and no bar can leave
    /// the rest…peak span.
    static func pulseHeight(bar index: Int, at time: TimeInterval, config: Configuration = .standard) -> CGFloat {
        let strokes = time / config.pulsePeriod - Double(index) / Double(config.barCount)
        let rise = (1 - cos(.pi * strokes)) / 2
        return config.restHeight + (config.peakHeight - config.restHeight) * CGFloat(rise)
    }

    /// The frozen equalizer, as fractions of the rest→peak span. One bar down,
    /// one up and two between: enough that the row reads as levels rather than as
    /// the flat block four equal bars draw. It repeats if a skin ever asks for
    /// more bars than it has entries.
    static let stillProfile: [Double] = [0, 1, 0.5, 0.75]

    /// The height each bar HOLDS when it does not pulse — the form, which the
    /// vetoes do not get to decide. They forbid movement and spending, not
    /// information, and on the compact surfaces this glyph is the only thing that
    /// says playing at all (`CardView.compactContent`): with the pulse vetoed and
    /// every bar at rest, playing and paused drew the same four 4 pt stubs.
    /// Playing under a veto therefore keeps a staggered silhouette and does not
    /// move; paused is flat at rest, whatever the vetoes say.
    static func stillHeights(
        animating: Bool, reduceMotion: Bool, lowPower: Bool, shown: Bool = true, config: Configuration = .standard
    ) -> [CGFloat] {
        let vetoed = animating
            && !dances(animating: animating, reduceMotion: reduceMotion, lowPower: lowPower, shown: shown)
        guard vetoed, !stillProfile.isEmpty else {
            return Array(repeating: config.restHeight, count: config.barCount)
        }
        let span = config.peakHeight - config.restHeight
        return (0..<config.barCount).map { index in
            config.restHeight + span * CGFloat(stillProfile[index % stillProfile.count])
        }
    }
}
