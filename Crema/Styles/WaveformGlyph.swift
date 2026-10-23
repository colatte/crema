import SwiftUI

/// Playback indicator: thin center-anchored bars pulsing symmetrically between
/// rest and peak, each offset a fraction of a cycle from its neighbor — one rises
/// while another falls, the live-equalizer read. (Bottom-anchored bars read as a
/// column chart; synchronized ones as a blinking block.) Pure state-driven
/// animation — no audio capture, no spectrum analysis. The family shares one
/// tuning (`Configuration.standard`); a skin passes its own Configuration only
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

    /// `.animation(_, value:)` only fires on a change after mounting, and the
    /// glyph usually mounts with `animating` already true (surfacing mid-
    /// playback) — the bars would freeze at their peaks. This internal phase
    /// flips right after insertion (onAppear), a real change, so the pulse
    /// provably starts. Purely visual ephemeral state.
    ///
    /// It tracks `shouldDance`, not `animating`, and that is what makes every veto
    /// live: Reduce Motion can be switched on, Low Power Mode can engage and the
    /// surface can hide with the glyph already mounted and pulsing, and a phase
    /// latched at mount would keep the bars dancing under any of them. The sibling
    /// gates follow a live flip for free, because they read their input inside a
    /// body, which re-runs; a phase in @State has to be told. One derived value
    /// carries every veto, so the `onChange` below stays keyed on it rather than
    /// growing a key per input — which is how one of them ends up watched and
    /// another forgotten.
    ///
    /// It carries the PULSE alone. The form the bars hold when it is false comes
    /// from `stillHeights`, read inside the body: a veto arriving mid-playback
    /// takes the movement away and leaves the silhouette, and that change needs
    /// no phase because a body re-run already carries it.
    @State private var dancing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Nil off the panels (previews, the Settings tiles): no mirror, no veto.
    @Environment(\.lowPowerMode) private var lowPowerMode
    @Environment(\.surfaceIsShown) private var shown
    @Environment(\.artworkAccent) private var accent
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    /// Settle time when playback pauses: quick enough to read as an
    /// immediate freeze, slow enough not to snap. Not part of Configuration —
    /// the pause reaction should feel identical everywhere, even for a skin
    /// that overrides the pulse itself.
    private static let freezeDuration: Double = 0.25

    var body: some View {
        let still = Self.stillHeights(
            animating: animating, reduceMotion: reduceMotion, lowPower: lowPower, shown: shown, config: config
        )
        HStack(alignment: .center, spacing: config.barSpacing) {
            ForEach(0..<config.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: config.barCornerRadius, style: .continuous)
                    .frame(
                        width: config.barWidth,
                        height: dancing ? config.peakHeight : still[index]
                    )
                    // One flip of `dancing` starts the endless bounce
                    // (repeatForever autoreverses between rest and peak); the
                    // per-bar delay staggers the phases evenly across one
                    // cycle. Flipping back replaces it with a plain settle onto
                    // whatever height the bar holds still at — flat at rest when
                    // playback stopped, the frozen equalizer when a veto stopped
                    // the movement and playback did not.
                    .animation(
                        dancing
                            ? .easeInOut(duration: config.pulsePeriod)
                            .repeatForever(autoreverses: true)
                            .delay(config.pulsePeriod * Double(index) / Double(config.barCount))
                            : .easeOut(duration: Self.freezeDuration),
                        value: dancing
                    )
            }
        }
        .frame(height: config.peakHeight)
        // The bars take the cover's tone, styled here so all skins tint
        // identically and lifted as far as the contrast setting's background
        // needs (`ArtworkAccent.Tone.displayComponents`). No usable tone ⇒ the
        // neutral secondary.
        .foregroundStyle(
            accent.map { AnyShapeStyle($0.color(contrast: colorSchemeContrast)) } ?? AnyShapeStyle(.secondary)
        )
        .onAppear { dancing = shouldDance }
        .onChange(of: shouldDance) { _, dance in
            dancing = dance
        }
    }

    /// Every input of the pulse in one value, so the `onChange` above fires on either
    /// veto as well as on play/pause: motion is theirs to stop at any moment, not
    /// only at the next transport event. Read inside the body, so an @Observable
    /// mirror flip invalidates it like the accessibility preference does.
    private var shouldDance: Bool {
        Self.dances(animating: animating, reduceMotion: reduceMotion, lowPower: lowPower, shown: shown)
    }

    private var lowPower: Bool { lowPowerMode?.isLowPower ?? false }

    /// The rule itself, pure and static so it is testable without a rendered view.
    /// Two vetoes, neither reducible to the other: Reduce Motion is the user's
    /// standing request that nothing move, and Low Power Mode is the system's
    /// request that nothing be spent on motion — a repeatForever pulse on a
    /// surface that sits over the menu bar is exactly what it means. An absent
    /// mirror means nobody wired one, which is no veto. A hidden surface stops it
    /// as a veto does (`surfaceIsShown`): it still draws the glyph it faded out
    /// with, and keeps the silhouette it faded out on.
    ///
    /// It decides the PULSE and nothing else; the silhouette is `stillHeights`.
    static func dances(animating: Bool, reduceMotion: Bool, lowPower: Bool, shown: Bool = true) -> Bool {
        animating && shown && SurfaceAnimation.allowsPerpetualMotion(reduceMotion: reduceMotion, lowPower: lowPower)
    }

    /// The frozen equalizer, as fractions of the rest→peak span. One bar down,
    /// one up and two between: enough that the row reads as levels rather than as
    /// the flat block four equal bars draw. It repeats if a skin ever asks for
    /// more bars than it has entries.
    static let stillProfile: [Double] = [0, 1, 0.5, 0.75]

    /// The height each bar HOLDS — the form, which the vetoes do not get to
    /// decide. They forbid movement and spending, not information, and on the
    /// compact surfaces this glyph is the only thing that says playing at all
    /// (`CardView.compactContent`): with the pulse vetoed and every bar at rest,
    /// playing and paused drew the same four 4 pt stubs. Playing under a veto
    /// therefore keeps a staggered silhouette and does not move; paused is flat
    /// at rest, whatever the vetoes say.
    ///
    /// While the pulse is ON this is its FLOOR, not the silhouette: the endless
    /// autoreverse animates between the height declared here and the peak, so a
    /// bar handed its profile height would pulse from peak to peak — invisibly.
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
