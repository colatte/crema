import SwiftUI

/// Decorative playback indicator: thin center-anchored bars pulsing
/// symmetrically between rest and peak, each offset a fraction of a cycle from
/// its neighbor — one rises while another falls, the live-equalizer read.
/// (Bottom-anchored bars read as a column chart; synchronized ones as a
/// blinking block.) Pure state-driven animation — no audio capture, no
/// spectrum analysis. The family shares one tuning (`Configuration.standard`);
/// a skin passes its own Configuration only when it actually diverges.
struct WaveformGlyph: View {
    struct Configuration {
        var barCount: Int
        var barWidth: CGFloat
        var barSpacing: CGFloat
        var barCornerRadius: CGFloat
        var restHeight: CGFloat
        var peakHeight: CGFloat
        var pulsePeriod: Double

        /// The family's shared tuning — every skin uses it today. Override per
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
    /// It tracks `shouldDance`, not `animating`: Reduce Motion can be switched on
    /// with the glyph already mounted and pulsing, and a phase latched from the
    /// preference only at mount would keep the bars dancing under it. The sibling
    /// gates follow a live flip for free — they read the preference inside a
    /// body, which re-runs; a phase in @State has to be told.
    @State private var dancing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artworkAccent) private var accent

    /// Settle time when playback pauses: quick enough to read as an
    /// immediate freeze, slow enough not to snap. Not part of Configuration —
    /// the pause reaction should feel identical everywhere, even for a skin
    /// that overrides the pulse itself.
    private static let freezeDuration: Double = 0.25

    var body: some View {
        HStack(alignment: .center, spacing: config.barSpacing) {
            ForEach(0..<config.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: config.barCornerRadius, style: .continuous)
                    .frame(
                        width: config.barWidth,
                        height: dancing ? config.peakHeight : config.restHeight
                    )
                    // One flip of `dancing` starts the endless bounce
                    // (repeatForever autoreverses between rest and peak); the
                    // per-bar delay staggers the phases evenly across one
                    // cycle. Flipping back replaces it with a plain settle —
                    // the freeze that reads as "paused".
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
        // The bars take the cover's tone (the styling moved in here so all
        // skins tint identically), clamped into the single dark-surface band.
        // No usable tone ⇒ the neutral secondary.
        .foregroundStyle(accent.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
        .onAppear { dancing = shouldDance }
        .onChange(of: shouldDance) { _, dance in
            dancing = dance
        }
    }

    /// Both inputs of the pulse in one value, so the `onChange` above fires on a
    /// preference flip as well as on play/pause: motion is the accessibility
    /// preference's to veto at any moment, not only at the next transport event.
    private var shouldDance: Bool {
        animating && !reduceMotion
    }
}
