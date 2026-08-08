import SwiftUI

/// The time, for the one surface that covers the system's own.
///
/// Pure and separate because all three interesting things about a clock are
/// answerable without one: how it reads in a language, when it should next
/// change, and what it must never do to either.
enum LockClock {
    /// The time with no seconds, in whatever the reader's region says that
    /// means — 12-hour with a marker, 24-hour, or the leading-zero-less forms
    /// some locales use. Measured across four: `11:04 AM` (en_US), `19:04`
    /// (en_GB), `15:04` (pt_BR), `3:04` (ja_JP).
    ///
    /// `locale` and `timeZone` are REQUIRED, and their absence would be the
    /// bug. A `Date.FormatStyle` already carries the autoupdating pair, so a
    /// default here would read the machine — and then a test asserting `2:04 PM`
    /// is green only where the runner's region matches the author's. This is the
    /// class CLAUDE.md's TDD section names: a clock parameter with a production
    /// default is a wall clock injected without anyone writing `Date()`.
    static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// Weekday, month and day, abbreviated, in the locale's own order — never a
    /// composed string. `Sun, Aug 9` / `dom., 9 de ago.` / `8月10日(月)`, and the
    /// separators come from the locale rather than from us.
    ///
    /// Field selection, not display order: writing `.day().month().weekday()`
    /// returns byte-identical output. And deliberately not the `.abbreviated`
    /// date preset, which drags the year in (`Aug 9, 2026`) — nobody reading a
    /// lock screen is unsure what year it is.
    static func day(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// How long until the displayed minute becomes wrong.
    ///
    /// Sampled from the instant the caller woke, never accumulated — the rule
    /// `sample-dont-integrate` already governs the playback position, and here it
    /// is the whole reason a lock-screen clock can be correct at all.
    ///
    /// MEASURED, and worth carrying because the raw number reads like a failure.
    /// `scripts/probes/lockscreen-clock-tick.swift`, 2026-08-08, 369 s over the
    /// shield: the loop delivered 2 of 6 owed wakes. That is the MACHINE
    /// SLEEPING, not the timer failing — `pmset -g log` dates it exactly (idle
    /// sleep entered 09:53:58 for 282 s, wake 09:58:40, on a Mac set to sleep
    /// after 1 minute). `Task.sleep` waits on an absolute `ContinuousClock`
    /// deadline and that clock counts THROUGH suspension, so the deadline is
    /// already past on resume and the next wake carries the current minute:
    /// reproduced with SIGSTOP across five boundaries, the pending sleep returned
    /// 2 ms after SIGCONT with the right time and the five missed boundaries
    /// collapsed into one. The field run proves it too — the loop is sequential
    /// and only one boundary fell inside the awake window, so a count of 2 is
    /// unreachable without the resume fire.
    ///
    /// So the honest bound is not "one stale minute": the surface can hold a
    /// minute as old as the machine's sleep. What it can never do is show a stale
    /// minute to anyone, because the screen is dark for exactly the interval that
    /// staleness lasts. This is also why no `NSSystemClockDidChange` observer is
    /// owed, and why a dispatch timer would be the wrong fallback — it schedules
    /// on the same suspended machine and buys nothing this does not already have.
    /// When to distrust it: a wake that leaves the time visibly behind. Re-run
    /// the probe.
    ///
    /// The answer is always inside (0, 60], and by construction rather than by a
    /// guard. `truncatingRemainder` never returns the divisor, so `elapsed` is
    /// in [0, 60) and the difference cannot reach zero — a wake landing exactly
    /// on the boundary asks for a whole minute, not for nothing. A clamp here
    /// looked prudent and was dead code: it survived a mutation because no input
    /// can reach it, which is the tautology CLAUDE.md warns about.
    static func secondsUntilNextMinute(after date: Date) -> Double {
        let intoMinute = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60)
        // Dates before the reference epoch give a NEGATIVE remainder, and this
        // is the one branch that earns its place: without it such a date asks
        // for a sleep longer than the interval being measured.
        let elapsed = intoMinute < 0 ? intoMinute + 60 : intoMinute
        return 60 - elapsed
    }
}

/// The clock drawn over the expanded lock surface.
///
/// It exists because the backdrop covers the system's clock, and for no other
/// reason: the collapsed card covers nothing, so nothing is drawn there. Two
/// clocks on one screen is what this is arranged to avoid, not a look.
///
/// ## Why it answers to none of the drift vetoes
///
/// `ArtworkDrift` gates the backdrop on Reduce Motion, Low Power Mode and a
/// three-minute settle. None reaches here, and the third points the opposite
/// way. Reduce Motion has no motion to gate — a digit replacing another carries
/// no animation, and appearing rides the surface's existing morph. Low Power's
/// stated cost is a `repeatForever` transform; this wakes once a minute, on a
/// surface whose body already rebuilds sixty times more often, unvetoed, while
/// music plays. And `settlesAfter` exists because a picture still moving on an
/// idle desk at 4 a.m. is wear — whereas a clock still running at 4 a.m. is the
/// entire point of one. Folding it into `drifts` would ship a clock frozen at
/// the minute of the lock, which is worse than no clock.
///
/// ## Why it owns a timer instead of riding the surface's 1 Hz rebuild
///
/// The position tick looks like a free minute hand and is not: the adapter
/// installs it only while something is PLAYING, and pausing does not collapse
/// this surface (it clears on the media stopping, and a paused track is still a
/// track). Pause, lock, walk away, and a clock riding that tick shows the minute
/// of the pause all night.
///
/// It holds `any SleepClock`, like the other nineteen clock holders in the app.
/// An earlier version was generic over it, justified by diffability — measured
/// false: the body re-evaluates 61 times a minute either way (generic 61,
/// existential 61), and the only lever that moves it is whether the displayed
/// instant is `@State` at all (1-2 without). 61 evaluations of two `Text`s is not
/// a cost worth a type parameter, and the real reason this is its own View
/// stands untouched: a MINUTE tick invalidates one line of text instead of the
/// whole card.
struct LockClockView: View {
    let clock: any SleepClock

    /// The wall clock is read here and nowhere else. What a test can own are the
    /// three pure rules above; a view that shows the time has to ask the machine
    /// what time it is.
    @State private var now = Date()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: LockWidgetMetrics.gap) {
            // Two `Text`s rather than one interpolated string: `Text("\(a) \(b)")`
            // is a `LocalizedStringKey` lookup for a key nobody wrote, invisible
            // to the catalog checker and to the translator both.
            Text(LockClock.time(now, locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent))
                .font(.title.weight(.semibold))
            Text(LockClock.day(now, locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        // Digit width, not digit count: this equalises `1` against `8` so the
        // pair does not jitter each minute. It cannot fix a 12-hour locale's
        // `9:59` becoming `10:00`, which changes the character COUNT and
        // re-centres the block — visible only in English, and small at this size.
        .monospacedDigit()
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 2)
        // One VoiceOver stop reading "4:04 PM, Sun, Aug 9", not two loose ones.
        // No `.accessibilityLabel`: it would REPLACE the content and delete the
        // time it is there to announce.
        .accessibilityElement(children: .combine)
        // The surface below owns every click; a clock has nothing to answer.
        // This is about hit testing only — taking it out of the accessibility
        // tree is a different modifier, and this one is not it.
        .allowsHitTesting(false)
        .task {
            await LockClockTicker(clock: clock, now: { Date() }).run { now = $0 }
        }
    }
}

/// The loop, extracted from the view so the property everything rests on is a
/// test instead of a sentence.
///
/// That property is the RE-ASK: the wait is recomputed from the instant each
/// wake actually happened, never reused. It is what makes a resume from system
/// sleep show the current minute rather than the one the deadline was set for —
/// and while it lived inline, hardcoding the wait to 60 left the whole suite
/// green. Two more become provable with it: that cancellation ends the loop, and
/// that any other error does not.
struct LockClockTicker {
    let clock: any SleepClock
    /// Reads the wall clock. Injected so a test can move time between wakes and
    /// watch the next wait be asked afresh — with a real `Date()` inside the loop
    /// there is nothing to observe.
    let now: @Sendable () -> Date

    @MainActor
    func run(_ tick: @MainActor (Date) -> Void) async {
        while !Task.isCancelled {
            let wait = LockClock.secondsUntilNextMinute(after: now())
            do {
                try await clock.sleep(for: wait)
            } catch {
                // Every error takes the same exit, and the single branch is the
                // point. A refused wait means THIS wait did not complete, not
                // that time stopped — retiring here would freeze the displayed
                // minute for the rest of the lock, which an earlier version did
                // behind a comment claiming cancellation was the only way out.
                // Cancellation needs no case of its own: it lands here too, and
                // the `isCancelled` check above ends the loop on the next pass.
                // A separate `catch is CancellationError { return }` was written
                // first and removed — no test could tell the two apart, because
                // there is no behaviour between them, only one wasted call.
                continue
            }
            tick(now())
        }
    }
}
