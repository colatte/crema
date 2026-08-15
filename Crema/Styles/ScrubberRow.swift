import SwiftUI

/// Shared thin progress row: elapsed time, the track bar and (optionally) the
/// duration at the trailing end. The reference layout shows both times at the
/// bar's ends; only the Notch band drops the trailing one, and only because a
/// second label there comes straight out of the drag range — its content is
/// ~101 pt wide at the narrowest scale mode (NotchWidthBudgetTests). The card and
/// the classic block are several times that wide and show both. Position and
/// duration come from the caller's live `nowPlaying` read; the scrub intent flows
/// back through the caller into the Coordinator.
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

    private var showsHours: Bool { Self.showsHours(duration: duration) }

    /// The label's shape, decided by the TRACK's length so the two labels never
    /// disagree about their own. With no duration the shape is FIXED at m:ss
    /// rather than derived from the running position: a live stream would cross
    /// an hour with the row already on screen and rewrite its own labels in the
    /// air, widening the elapsed number from 22.33 to 38.25 pt (measured) and
    /// shoving the bar beside it. The cost is honest and bounded — a stream past
    /// an hour reads 60:00 and keeps counting minutes — and it buys a number that
    /// never moves under the eye.
    static func showsHours(duration: Double?) -> Bool {
        guard let duration else { return false }
        return TimeLabel.reachesAnHour(duration)
    }

    /// The bar's 0…1 fill. A fraction needs a denominator, and live content
    /// reports none: with no duration the bar is BARE, the same "zero stays
    /// empty" rule `CapsuleTrack.capsuleFillWidth` draws. It used to stand a
    /// `max(position, 1)` span in for the missing one, which pins the fraction at
    /// 1 from the first second onward — a radio stream drawing a permanently
    /// finished track. Nothing interactive is lost: the row is not a control
    /// without a duration (`interactive`).
    static func fill(position: Double, duration: Double?) -> Double {
        guard let duration, duration > 0 else { return 0 }
        return min(max(position / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeLabel(draft ?? position, showsHours: showsHours))
            track
            if showsDuration, let duration {
                Text(timeLabel(duration, showsHours: showsHours))
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }

    /// The same bar the HUD draws, and that is the point of it being shared.
    ///
    /// It used to be a stock `Slider` tinted with the artwork accent: a thumb
    /// always visible, a coloured fill. Two rows above it in the lock card — a
    /// surface since removed whole — sat the HUD's own bar, which had already
    /// been measured off the Tahoe banner
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
        // The stand-in span survives HERE and nowhere else: the accessibility
        // Slider below needs a non-empty range even on a row it cannot adjust,
        // and the gesture answers 0 for a zero span anyway. The FILL no longer
        // reads it — a stand-in denominator is a lie about how far in we are.
        let span = duration ?? max(position, 1)
        let shown = draft ?? position
        GeometryReader { geometry in
            CapsuleTrack(
                value: Self.fill(position: shown, duration: duration),
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
        // The dead control has to LOOK dead, at the transport's own opacity: the
        // buttons a row below already dim when their command path degrades, and a
        // bar that stayed fully lit beside them read as the one live control on a
        // player where nothing responds. Only the bar dims — the elapsed label
        // keeps counting on a stream with no duration, and that number is
        // information rather than an affordance.
        .opacity(isLive ? 1 : TransportControls.disabledOpacity)
        // `disabled` rather than `allowsHitTesting`: it stops the gesture AND
        // takes the accessibility element out of adjustability. Hit testing
        // alone left VoiceOver able to scrub a row with no duration to scrub.
        .disabled(!isLive)
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
    private var isLive: Bool { Self.isLive(interactive: interactive, isEditing: isEditing) }

    /// A live gesture is never yanked away: a command failure flipping `enabled`
    /// (or a payload dropping the duration) mid-drag must degrade AFTER the
    /// release — neither killing the tracking under the finger nor dimming the
    /// bar beneath it. So the in-flight gesture keeps the row live on its own.
    static func isLive(interactive: Bool, isEditing: Bool) -> Bool {
        interactive || isEditing
    }

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
    private func timeLabel(_ seconds: Double, showsHours: Bool) -> String {
        let value = Duration.seconds(max(0, seconds))
        return showsHours
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
