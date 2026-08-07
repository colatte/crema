import SwiftUI

/// Shared thin progress row: elapsed time, mini slider and (optionally) the
/// duration at the trailing end. The reference layout shows both times at the
/// bar's ends; narrow skins keep only the elapsed label to protect the drag
/// range. Position and duration come from the caller's live `nowPlaying` read;
/// the scrub intent flows back through the caller into the Coordinator.
///
/// The drag owns the shown position: while editing, the slider reads and
/// writes `draft` (ephemeral, purely visual — the gesture's in-flight value),
/// so the 1 Hz position tick re-rendering underneath cannot pull the thumb
/// against the finger — and no intent fires per delta, so a drag is ONE seek
/// on release, never a storm of per-pixel subprocess commands. `isEditing`
/// (HUDLevelSlider's shape) is the gesture sentinel: a value written OUTSIDE
/// an edit session (a click on the track whose callbacks skip the edit pair,
/// a keyboard/accessibility adjustment) seeks immediately — tap-to-seek stays
/// guaranteed by construction, independent of the stock Slider's callback
/// order — and can never latch a stale draft. The release hands the draft to
/// `onScrub` before clearing it; the Coordinator writes the target
/// optimistically in the same MainActor turn, so the post-release render
/// reads the same value and the thumb never blinks.
struct ScrubberRow: View {
    let position: Double
    let duration: Double?
    let enabled: Bool
    var showsDuration = false
    let onScrub: (Double) -> Void

    @Environment(\.artworkAccent) private var accent
    @State private var draft: Double?
    @State private var isEditing = false

    /// Both labels follow the TRACK's length, so they never disagree about
    /// their own shape. Live content reports no duration at all, and there the
    /// elapsed time is the only number on screen — m:ss until it earns hours.
    private var reachesAnHour: Bool {
        TimeLabel.reachesAnHour(duration ?? position)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel(draft ?? position, reachesAnHour: reachesAnHour))
            Slider(
                value: Binding(
                    get: { draft ?? position },
                    set: { value in
                        if isEditing { draft = value } else { onScrub(value) }
                    }
                ),
                in: 0...(duration ?? max(position, 1)),
                onEditingChanged: { editing in
                    isEditing = editing
                    guard !editing else { return }
                    if let draft { onScrub(draft) }
                    draft = nil
                }
            )
            .controlSize(.mini)
            // The elapsed fill takes the cover's tone; nil keeps the system
            // default. Labels stay neutral — the tint is a suggestion.
            .tint(accent?.color)
            // A live gesture is never yanked away: a command failure flipping
            // `enabled` (or a payload dropping the duration) mid-drag must
            // degrade AFTER the release, not kill the tracking under the finger.
            .disabled((duration == nil || !enabled) && !isEditing)
            if showsDuration, let duration {
                Text(timeLabel(duration, reachesAnHour: reachesAnHour))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// Locale-aware via FormatStyle — never hand-assembled digits.
    ///
    /// The pattern is chosen by the TRACK's length, not by the value being
    /// printed, so the elapsed and total labels always have the same shape: a
    /// 1h20m recording reads `0:05:00 / 1:20:00`, never `5:00 / 1:20:00`.
    private func timeLabel(_ seconds: Double, reachesAnHour: Bool) -> String {
        let value = Duration.seconds(max(0, seconds))
        return reachesAnHour
            ? value.formatted(.time(pattern: .hourMinuteSecond))
            : value.formatted(.time(pattern: .minuteSecond))
    }
}

/// When a duration stops fitting in `m:ss`.
///
/// `.minuteSecond` does not roll over into hours — it keeps counting minutes,
/// and past a thousand it takes the locale's grouping separator with it.
/// Measured: 3600 s prints `60:00`, 7200 s prints `120:00`, and 86 000 s prints
/// `1.433:20` on a pt-BR Mac. The border admits any duration under 24 h
/// (`AdapterPayloadTranslation`), so an audiobook, a DJ set or a long stream
/// reaches this in ordinary use — it is not an edge case, it is the whole
/// non-music half of what people play.
enum TimeLabel {
    static let secondsInAnHour: Double = 3600

    static func reachesAnHour(_ seconds: Double) -> Bool {
        seconds >= secondsInAnHour
    }
}
