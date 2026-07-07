import SwiftUI

/// Decorative playback indicator: thin center-anchored bars pulsing
/// symmetrically between rest and peak, each offset a fraction of a cycle from
/// its neighbor — one rises while another falls, the live-equalizer read.
/// (Bottom-anchored bars read as a column chart; synchronized ones as a
/// blinking block.) Pure state-driven animation — no audio capture, no
/// spectrum analysis. All dimensions and rhythm come from the caller: each
/// skin owns its metrics.
struct WaveformGlyph: View {
    struct Configuration {
        var barCount: Int
        var barWidth: CGFloat
        var barSpacing: CGFloat
        var barCornerRadius: CGFloat
        var restHeight: CGFloat
        var peakHeight: CGFloat
        var pulsePeriod: Double
    }

    let animating: Bool
    let config: Configuration

    /// `.animation(_, value:)` only fires on a change after mounting, and the
    /// glyph usually mounts with `animating` already true (surfacing mid-
    /// playback) — the bars would freeze at their peaks. This internal phase
    /// flips right after insertion (onAppear), a real change, so the pulse
    /// provably starts. Purely visual ephemeral state.
    @State private var dancing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.artworkAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    /// Settle time when playback pauses: quick enough to read as an
    /// immediate freeze, slow enough not to snap. The only waveform timing
    /// that is not per-skin — the pause reaction should feel identical
    /// everywhere (the per-skin Configuration owns the pulse itself).
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
        // skins tint identically), resolved against this subtree's scheme —
        // the notch forces dark. No usable tone ⇒ the neutral secondary.
        .foregroundStyle(accent.map { AnyShapeStyle($0.color(for: colorScheme)) } ?? AnyShapeStyle(.secondary))
        .onAppear { dancing = animating && !reduceMotion }
        .onChange(of: animating) { _, playing in
            dancing = playing && !reduceMotion
        }
    }
}
