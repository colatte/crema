import Foundation
import Testing
@testable import Crema

/// The clock's three pure rules: how it reads, when it next changes, and the
/// promise that neither is decided by the machine running the test.
///
/// Every case pins BOTH the locale and the time zone. A `Date.FormatStyle`
/// carries the autoupdating pair by default, so an assertion written without
/// them is green only where the runner's region matches the author's — measured
/// on this Mac, which reports `pt_BR` and `America/Cuiaba`, the same instant is
/// `4:04 PM` in en_US and `16:04` here.
struct LockClockTests {

    /// One fixed instant, so nothing here can be true by accident of the day it
    /// runs: 2026-08-09, 19:04:37 UTC.
    private static let instant = Date(timeIntervalSince1970: 1_786_302_277)

    /// `.gmt` rather than `TimeZone(identifier: "UTC")`, which is optional and
    /// would need a force unwrap this house does not allow in tests.
    private static let utc = TimeZone.gmt

    /// What separates a 12-hour time from its AM/PM marker: U+202F, NARROW
    /// NO-BREAK SPACE, not the ordinary U+0020. Apple's ICU switched to it, and
    /// the two are indistinguishable on screen — an assertion typed with a plain
    /// space fails with a diff that reads `"7:04 PM" == "7:04 PM"`, which is
    /// where twenty minutes go. Written as an escape so the next reader sees the
    /// character rather than inheriting an invisible one by copy-paste.
    private static let thinSpace = "\u{202F}"

    // MARK: - How it reads

    @Test func theTimeFollowsTheRegionsOwnClockConvention() {
        // The point of a FormatStyle rather than a written format: 12-hour with
        // a marker, 24-hour, and the leading-zero-less forms are not ours to
        // choose per language — the locale already decided.
        #expect(LockClock.time(Self.instant, locale: Locale(identifier: "en_US"), timeZone: Self.utc)
            == "7:04\(Self.thinSpace)PM")
        #expect(LockClock.time(Self.instant, locale: Locale(identifier: "pt_BR"), timeZone: Self.utc)
            == "19:04")
        #expect(LockClock.time(Self.instant, locale: Locale(identifier: "en_GB"), timeZone: Self.utc)
            == "19:04")
    }

    @Test func theTimeCarriesNoSeconds() {
        // A lock screen clock that ticks every second would wake sixty times as
        // often for a digit nobody reads, and the tick loop is built around the
        // minute boundary. If the style ever grew seconds, the display and the
        // wake schedule would disagree.
        let rendered = LockClock.time(Self.instant, locale: Locale(identifier: "pt_BR"), timeZone: Self.utc)
        #expect(!rendered.contains("37"))
        #expect(rendered.filter { $0 == ":" }.count == 1)
    }

    @Test func theTimeZoneIsHonouredRatherThanTheMachines() throws {
        // The parameter exists FOR this: without it the same instant renders as
        // whatever the runner's region says, and the test asserts the runner.
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(LockClock.time(Self.instant, locale: Locale(identifier: "en_US"), timeZone: tokyo)
            == "4:04\(Self.thinSpace)AM")
    }

    @Test func theDateIsAbbreviatedInEachLanguagesOwnOrder() {
        // Never composed by us: the separators, the order and the abbreviations
        // all come from the locale. pt-BR brings its own comma and periods,
        // which is why there is no separator glyph anywhere in the view.
        #expect(LockClock.day(Self.instant, locale: Locale(identifier: "en_US"), timeZone: Self.utc)
            == "Sun, Aug 9")
        #expect(LockClock.day(Self.instant, locale: Locale(identifier: "pt_BR"), timeZone: Self.utc)
            == "dom., 9 de ago.")
    }

    @Test func theDateCarriesNoYear() {
        // The mutation this kills: `Date.FormatStyle(date: .abbreviated)` looks
        // like the same thing and drags the year in ("Aug 9, 2026"). Nobody
        // reading a lock screen is unsure what year it is, and the extra field
        // is what pushes the pair off centre.
        for identifier in ["en_US", "pt_BR", "en_GB", "ja_JP"] {
            let rendered = LockClock.day(
                Self.instant, locale: Locale(identifier: identifier), timeZone: Self.utc
            )
            #expect(!rendered.contains("2026"), "\(identifier) rendered a year: \(rendered)")
        }
    }

    // MARK: - When it next changes

    @Test func theWaitLandsOnTheMinuteBoundary() {
        // 19:04:37 leaves 23 seconds. Sampled from the instant rather than
        // accumulated, so a late wake asks a fresh question instead of
        // inheriting the drift.
        #expect(LockClock.secondsUntilNextMinute(after: Self.instant) == 23)
    }

    @Test func aWakeExactlyOnTheBoundaryWaitsAWholeMinute() {
        // Zero would sleep for nothing and spin the loop until the clock crossed
        // the boundary — a tight loop over a lock screen, all night.
        let onTheMinute = Date(timeIntervalSince1970: 1_786_302_240)
        #expect(LockClock.secondsUntilNextMinute(after: onTheMinute) == 60)
    }

    @Test func everyInstantInAMinuteAsksForSomethingSleepable() {
        // The property that matters more than any single value: the wait is
        // always inside (0, 60], so the loop can neither spin nor skip a minute.
        for offset in stride(from: 0.0, to: 60.0, by: 0.25) {
            let wait = LockClock.secondsUntilNextMinute(
                after: Self.instant.addingTimeInterval(offset)
            )
            #expect(wait > 0 && wait <= 60, "offset \(offset) asked for \(wait)")
        }
    }

    @Test func anInstantBeforeTheReferenceEpochDoesNotAskForMoreThanAMinute() {
        // `truncatingRemainder` is signed, so a date before 2001 would otherwise
        // produce a wait longer than the interval it is measuring.
        let ancient = Date(timeIntervalSinceReferenceDate: -137.5)
        let wait = LockClock.secondsUntilNextMinute(after: ancient)
        #expect(wait > 0 && wait <= 60)
    }
}

/// Where the backdrop stops, and why that boundary is one number rather than a
/// fraction of the display.
struct LockBackdropFadeTests {

    @Test func theFadeClearsExactlyWhereTheCardRefusesToGo() {
        // One measured fact, one constant. The backdrop becomes fully
        // transparent at the same line the collapsed card rests on, because
        // both mean "the login owns everything below this" — a second constant
        // would be a second answer that could drift from the first.
        #expect(LockWidgetMetrics.bottomInset == LockWidgetMetrics.clearBandFloor)
    }

    @Test func theFadeClearsTheLoginWithRoomToSpare() {
        // Measured 2026-08-08: the login's top edge is at or below 180 pt on the
        // author's 1512x982 panel. Anchoring at 300 leaves at least 120 pt, which
        // is what makes the "at or below" reading harmless — the scale's floor
        // was 180, so a true edge lower than that only widens the margin.
        let loginTopAtMost: CGFloat = 180
        #expect(LockWidgetMetrics.clearBandFloor >= loginTopAtMost)
        #expect(LockWidgetMetrics.clearBandFloor - loginTopAtMost >= 100)
    }

    @Test func theRampEndsNearHalfTheHeightOnThePanelItWasDesignedAgainst() {
        // The author asked for the fade to finish around half the height. This
        // records the arithmetic that satisfied it WITHOUT putting a fraction in
        // the code: on 982 pt, 300 + 180 = 480 is 51.1% from the top. The
        // assertion is deliberately loose — it pins the intent, not a pixel.
        let panelHeight: CGFloat = 982
        let rampTop = LockWidgetMetrics.clearBandFloor + LockWidgetMetrics.backdropFadeBand
        let fromTop = (panelHeight - rampTop) / panelHeight
        #expect(abs(fromTop - 0.5) < 0.05, "the ramp ends at \(fromTop * 100)% from the top")
    }

    @Test func theExpandedTilesBottomEdgeSitsInsideTheRampRatherThanBelowIt() {
        // Why the ramp is weighted instead of straight. The tile is centred, so
        // on this panel its bottom edge is at 341 — inside the 300…480 ramp. A
        // linear fall would leave the tile's bottom corners flanked by nearly
        // bare wallpaper; the stop table holds that region much higher.
        let panelHeight: CGFloat = 982
        let tileBottom = (panelHeight - LockWidgetMetrics.expandedSide) / 2
        let rampTop = LockWidgetMetrics.clearBandFloor + LockWidgetMetrics.backdropFadeBand
        #expect(tileBottom > LockWidgetMetrics.clearBandFloor)
        #expect(tileBottom < rampTop)
    }

    @Test func theClockClearsTheDeepestNotchThisRepoHasMeasured() {
        // 32 pt is the safe area on the 14-inch panel StylePreview describes and
        // the author's Mac reports. A clock at or under that would sit inside the
        // cutout on exactly the Macs this app was written for.
        #expect(LockWidgetMetrics.clockTopInset > StylePreview.notchedReference.safeTop)
    }
}

/// The loop, which used to live inline in the view and therefore could not be
/// tested at all. Its central property is the RE-ASK — the wait is recomputed
/// from the instant each wake actually happened — and while it was inline,
/// hardcoding that wait to 60 left the entire suite green.
@MainActor
struct LockClockTickerTests {

    /// Hands back a fixed instant that the test moves by hand, so a wait can be
    /// seen to be asked afresh rather than reused.
    private final class Hand: @unchecked Sendable {
        private let lock = NSLock()
        private var date: Date
        init(_ start: Date) { date = start }
        var now: Date { lock.withLock { date } }
        func set(_ new: Date) { lock.withLock { date = new } }
    }

    @Test func theWaitIsAskedAfreshAtEveryWake() async {
        // The mutation this exists for: replacing the computed wait with a
        // constant 60 passes every other test in the suite. Here the hand moves
        // between wakes, so a reused wait and a re-asked one differ.
        let clock = TestSleepClock()
        let hand = Hand(Date(timeIntervalSince1970: 1_786_302_240))   // exactly on a minute
        let ticker = LockClockTicker(clock: clock, now: { hand.now })
        var seen: [Date] = []
        let loop = Task { await ticker.run { seen.append($0) } }

        await clock.waitForSleep()
        #expect(clock.delays == [60], "on the boundary, a whole minute")

        // The machine slept through four boundaries; the wake lands at :17 past.
        hand.set(Date(timeIntervalSince1970: 1_786_302_240 + 257))
        clock.advance()
        await clock.waitForSleep(delay: 43)
        // 257 s later is 17 s into a minute, so 43 remain — NOT another 60.
        #expect(clock.delays == [60, 43])
        #expect(seen.count == 1, "one wake, carrying the instant it actually happened")

        loop.cancel()
        clock.advance()
        _ = await loop.value
    }

    @Test func cancellationEndsTheLoop() async {
        let clock = TestSleepClock()
        let hand = Hand(Date(timeIntervalSince1970: 1_786_302_240))
        let ticker = LockClockTicker(clock: clock, now: { hand.now })
        let loop = Task { await ticker.run { _ in } }
        await clock.waitForSleep()
        loop.cancel()
        // Returns rather than spinning: the value arriving at all is the
        // assertion, and the bounded helper is what fails loudly if it does not.
        _ = await loop.value
        #expect(clock.delays == [60])
    }

    @Test func anErrorThatIsNotCancellationDoesNotRetireTheClock() async {
        // The failure this forbids: one refused wait freezing the displayed
        // minute for the rest of the lock, behind a comment claiming
        // cancellation was the only way out.
        struct Refused: Error {}
        let clock = ThrowingOnceClock(error: Refused())
        let hand = Hand(Date(timeIntervalSince1970: 1_786_302_240))
        let ticker = LockClockTicker(clock: clock, now: { hand.now })
        let loop = Task { await ticker.run { _ in } }
        await eventually { clock.attempts >= 2 }
        #expect(clock.attempts >= 2, "the loop asked again after the refusal")
        loop.cancel()
        _ = await loop.value
    }
}

/// Throws on its first wait and parks forever after, so a loop that retires on a
/// non-cancellation error never reaches the second attempt.
private final class ThrowingOnceClock: SleepClock, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let error: any Error

    init(error: any Error) { self.error = error }

    var attempts: Int { lock.withLock { count } }

    func sleep(for _: Double) async throws {
        let attempt = lock.withLock { count += 1; return count }
        if attempt == 1 { throw error }
        try await Task.sleep(for: .seconds(3600))
    }
}
