import SwiftUI

/// Shared transport block of the reference layout: previous | play/pause |
/// next, one grouped cluster used identically by every skin's expanded state.
/// Every button disables (not hides) when its command path degrades — hiding
/// would shift the block and make the layout flinch with availability; a
/// grayed control reads as "exists, currently unavailable", like every other
/// degraded control in the app.
struct TransportControls: View {
    let isPlaying: Bool
    let enabled: Bool
    /// Skip availability is independent of play/pause: a source can accept
    /// one and reject the other (Coordinator.skipControlsEnabled).
    let skipEnabled: Bool
    var buttonSide: CGFloat = 28
    /// Play/pause, when a surface wants the primary action to READ as primary.
    /// Defaults to `buttonSide`, so every existing caller keeps three equal
    /// buttons and nothing moves.
    ///
    /// Three identical glyphs read as a row; two tiers read as a control. Both
    /// siblings measured this round do it — boring.notch runs 40x40 against
    /// 30x30 with a 26 pt glyph against 13, and Amberol's transport is
    /// described in its own source as a centred, oversized play button. The
    /// hit target of the skips is untouched: what changes is which one the eye
    /// lands on first.
    var primarySide: CGFloat?
    /// Breathing room between the three hit targets. The notch band passes a
    /// tighter value (NotchMetrics.controlsSpacing): its width shrinks with
    /// the display's scale mode and the default overflows the narrowest one.
    var spacing: CGFloat = 10
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void

    /// .plain buttons render custom labels unchanged when disabled — the
    /// affordance has to be drawn by hand or the dead control looks live.
    private static let disabledOpacity: Double = 0.35

    var body: some View {
        HStack(spacing: spacing) {
            skipButton(
                "backward.fill",
                label: String(localized: "transport.previousTrack", defaultValue: "Previous Track"),
                action: onPrevious
            )
            Button(action: onPlayPause) {
                let glyph = isPlaying ? "pause.fill" : "play.fill"
                let side = primarySide ?? buttonSide
                Image(systemName: glyph)
                    .font(side > buttonSide ? .title : .title3)
                    // The glyph alone is a ~15 pt target — too small for an
                    // ephemeral surface whose linger timers race the click.
                    .frame(width: side, height: side)
                    .contentShape(Rectangle())
                    // Native play↔pause replace, the same dynamic-glyph idiom as
                    // the HUD icons; keyed on the glyph so only the icon animates.
                    .symbolReplace(on: glyph)
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .opacity(enabled ? 1 : Self.disabledOpacity)
            skipButton(
                "forward.fill",
                label: String(localized: "transport.nextTrack", defaultValue: "Next Track"),
                action: onNext
            )
        }
        .frame(height: max(buttonSide, primarySide ?? buttonSide))
    }

    /// Skips render a step smaller than play/pause (the native hierarchy:
    /// the primary action reads largest) but keep the full hit target. The
    /// explicit label matters: the symbol-derived one says "Back"/"Forward"
    /// (navigation language), not what the button commands.
    private func skipButton(_ systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout)
                .frame(width: buttonSide, height: buttonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!skipEnabled)
        .opacity(skipEnabled ? 1 : Self.disabledOpacity)
        .accessibilityLabel(label)
    }
}
