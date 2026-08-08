import SwiftUI

/// Shared thin progress row: elapsed time, the track bar and (optionally) the
/// duration at the trailing end. The reference layout shows both times at the
/// bar's ends; narrow skins keep only the elapsed label to protect the drag
/// range. Position and duration come from the caller's live `nowPlaying` read;
/// the scrub intent flows back through the caller into the Coordinator.
///
/// The drag owns the shown position: while editing, the row reads and writes
/// `draft` (ephemeral, purely visual — the gesture's in-flight value), so the
/// 1 Hz position tick re-rendering underneath cannot pull the fill against the
/// finger — and no intent fires per delta, so a drag is ONE seek on release,
/// never a storm of per-pixel subprocess commands. A tap has no drag phase, so
/// `onEnded` carries it alone: tap-to-seek is guaranteed by the gesture's own
/// shape rather than by any callback ordering, which is what it used to depend
/// on. The release hands the position to `onScrub` before clearing the draft;
/// the Coordinator writes the target optimistically in the same MainActor turn,
/// so the post-release render reads the same value and the fill never blinks.
struct ScrubberRow: View {
    let position: Double
    let duration: Double?
    let enabled: Bool
    var showsDuration = false
    let onScrub: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var draft: Double?
    @State private var isEditing = false
    @State private var isHovered = false

    /// Both labels follow the TRACK's length, so they never disagree about
    /// their own shape. Live content reports no duration at all, and there the
    /// elapsed time is the only number on screen — m:ss until it earns hours.
    private var reachesAnHour: Bool {
        TimeLabel.reachesAnHour(duration ?? position)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel(draft ?? position, reachesAnHour: reachesAnHour))
            track
            if showsDuration, let duration {
                Text(timeLabel(duration, reachesAnHour: reachesAnHour))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// The same bar the HUD draws, and that is the point of it being shared.
    ///
    /// It used to be a stock `Slider` tinted with the artwork accent: a thumb
    /// always visible, a coloured fill. Two rows above it in the lock card sits
    /// the HUD's own bar, which had already been measured off the Tahoe banner
    /// and Control Center and decided — thumbless at rest, knob only under the
    /// pointer, fill WHITE (`docs/DECISIONS.md: hud-capsule-track`). The
    /// scrubber never adopted it, so one card carried two bars obeying opposite
    /// rules, and the one with a written decision behind it was the other one.
    ///
    /// The accent is gone with the thumb. The tone still reaches the surface
    /// through `artworkAccent`; the bar itself is a control, and the decision
    /// this now follows says a control reads white.
    ///
    /// Hover is LOCAL rather than the HUD's per-surface pointer signal: the HUD
    /// reveals its knob when the pointer is anywhere on a surface that hovering
    /// holds open, while a scrubber sitting inside a bigger card should answer
    /// to the pointer being on the BAR — which is also what Control Center does.
    @ViewBuilder private var track: some View {
        let span = duration ?? max(position, 1)
        let shown = draft ?? position
        GeometryReader { geometry in
            CapsuleTrack(
                value: span > 0 ? min(max(shown / span, 0), 1) : 0,
                showsKnob: (isHovered || isEditing) && interactive,
                reduceMotion: reduceMotion,
                layoutDirection: layoutDirection
            )
            // The whole row is the target, as the stock slider's track was: a
            // drag anywhere scrubs, and a tap (minimumDistance 0) seeks at the
            // touch point.
            .contentShape(Rectangle())
                .gesture(scrub(width: geometry.size.width, span: span))
        }
        .frame(height: CapsuleTrack.trackHitHeight)
        .onHover { isHovered = $0 }
        // A live gesture is never yanked away: a command failure flipping
        // `enabled` (or a payload dropping the duration) mid-drag must degrade
        // AFTER the release, not kill the tracking under the finger.
        //
        // `disabled` rather than `allowsHitTesting`: it stops the gesture AND
        // takes the accessibility element out of adjustability. Hit testing
        // alone left VoiceOver able to scrub a row with no duration to scrub.
        .disabled(!interactive && !isEditing)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { shown }, set: { onScrub($0) }),
                in: 0...span
            )
        }
        .accessibilityLabel(Text(String(
            localized: "scrubber.position", defaultValue: "Playback position"
        )))
    }

    private var interactive: Bool { duration != nil && enabled }

    /// One seek on release, never a storm of per-pixel subprocess commands —
    /// the reason the draft exists. A tap has no drag phase, so `onEnded` alone
    /// carries it, and `isEditing` is what tells the 1 Hz position tick to stop
    /// pulling the fill against the finger.
    private func scrub(width: CGFloat, span: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                isEditing = true
                draft = Self.position(atX: gesture.location.x, width: width, span: span,
                                      layoutDirection: layoutDirection)
            }
            .onEnded { gesture in
                let target = Self.position(atX: gesture.location.x, width: width, span: span,
                                           layoutDirection: layoutDirection)
                isEditing = false
                draft = nil
                onScrub(target)
            }
    }

    /// Pointer → seconds, over the FULL width: the ends of the row must reach 0
    /// and the duration, which is why this is not inset by the knob's half-width
    /// the way the knob's own travel is (`CapsuleTrack.knobCenterX`).
    static func position(
        atX x: CGFloat, width: CGFloat, span: Double, layoutDirection: LayoutDirection
    ) -> Double {
        guard width > 0, span > 0 else { return 0 }
        let physical = layoutDirection == .rightToLeft ? width - x : x
        return min(max(Double(physical / width), 0), 1) * span
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
