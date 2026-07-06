import SwiftUI

/// Shared thin progress row: elapsed time, mini slider and (optionally) the
/// duration at the trailing end. The reference layout shows both times at the
/// bar's ends; narrow skins keep only the elapsed label to protect the drag
/// range. Position and duration come from the caller's live `nowPlaying` read;
/// the scrub intent flows back through the caller into the Coordinator.
struct ScrubberRow: View {
    let position: Double
    let duration: Double?
    let enabled: Bool
    var showsDuration = false
    let onScrub: (Double) -> Void

    @Environment(\.artworkAccent) private var accent
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel(position))
            Slider(
                value: Binding(get: { position }, set: onScrub),
                in: 0...(duration ?? max(position, 1))
            )
            .controlSize(.mini)
            // The elapsed fill takes the cover's tone; nil keeps the system
            // default. Labels stay neutral — the tint is a suggestion.
            .tint(accent?.color(for: colorScheme))
            .disabled(duration == nil || !enabled)
            if showsDuration, let duration {
                Text(timeLabel(duration))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// Locale-aware m:ss via FormatStyle — never hand-assembled digits.
    private func timeLabel(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
    }
}
