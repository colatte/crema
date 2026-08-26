# Testing — the discipline, and what each clause cost

> The mechanism behind the rules CLAUDE.md states in one line each. Every clause
> below exists because a test lied once: it went green without looking, hung the
> whole suite, or failed for a reason foreign to its own thesis. Read this
> before writing a wait, before constructing a type that carries a clock, and
> before asserting that something did NOT happen.

## The frame

- Framework: **Swift Testing** (`@Test`/`#expect` macros; requires Xcode 16+ — the macOS 14 deployment target is unaffected).
- Tests live in `CremaTests/`, mirroring the app's structure; protocol mocks in `CremaTests/Mocks/`.

## Waits are wall-clock-bounded and MainActor-fair

Test waits (`eventually`/`eventuallyOffActor`/`waitForSleep`) are **never yield-counted**: a budget of scheduler slots runs out on a saturated machine (the parallel suite's cold start blew past any count), while a wall-clock deadline keeps running no matter who has the CPU. The idiom is a spin of yields on the healthy path + 1 ms micro-sleep backoff until the deadline (`TestSupport.boundedWaitDeadline`, 5 s) — this is the **narrow, deliberate exception** to "tests never really sleep": production timers stay on `SleepClock`; the micro-sleep is executor backoff inside the wait helper, not timer synchronization, and sleeping releases the actor to exactly the tasks being waited on.

`waitForSleep` is MainActor for FIFO fairness with the tasks that park the sleeps (an off-actor yield burns slots on the global executor before they get to run), and every blown deadline fails loudly at the next assertion instead of hanging the suite — the deadline-less continuation await has deadlocked the entire suite once before, and hung again in CI through the same door: raw `iterator.next()` on a stream becomes `BoundedStreamIterator` (bomb + bounded poll; timeout and end-of-stream both return nil and the next assertion fails naming the test), and a test double's wait for an event that has not arrived yet uses the same poll idiom, never a continuation.

The budget (`boundedWaitSeconds`, 5 s locally) is **environment-scalable** (`CREMA_TEST_WAIT_SECONDS`, crossing into the host via the `TEST_RUNNER_` prefix) because it is a saturation guard, not a correctness limit — CI widens it to 25 s.

**A test double that parks a real thread uses the SAME budget as the suite**, never a constant of its own: a fake prompt with a fixed 5 s deadline self-releases in the middle of a still-healthy wait when CI widens the budget to 25 s, and the test fails for a reason foreign to the contract (`MockAutomationPermission`). `NSCondition` + `Date` is correct there — the thing it doubles parks a real thread; what it must not do is keep the deadline private.

**`settle()` proves only MainActor negatives — a positive fact flipped off the actor takes `eventuallyOffActor`.** `settle()` is 50 MainActor yields by design (a drain, not a wait), and `resume()` on a parked continuation only transitions the task out of suspension — it runs again when ITS executor schedules it (SE-0300), so returning from a test-side `release()` proves nothing about the orphan's progress, and on a starved runner the 50 yields complete before the global pool ever runs the landing. Measured: CI red on `anAbandonedWriteThatLandsLateAppliesNoZombieState` (`hang.applied == []` behind a `settle()`), green on the same SHA in the next run; reproduced deterministically with a 100 ms cancellation-immune delay in the mock's landing — the same delay the off-actor wait then absorbed. Corollary for the reproduction itself: a cancellation-AWARE delay (`Task.sleep`) never fired, because the write deadline cancels the orphan and a sleep on a cancelled task returns at once — a mutant that observes cancellation cannot model the actuator whose whole point is ignoring it.

## `#expect` does not halt the test

An index precondition (a `count` followed by a subscript, a `!` on an optional the previous line checked) uses `try #require` or a whole-collection assertion: a trap yields no attributed failure — it kills the process, takes the in-flight siblings with it, and the `Test run with N tests` line **never prints**, which is precisely the verdict this house trusts (measured: SIGTRAP, exit 5, siblings without a result).

## A test double never carries a real wall clock

The key window running on a default `Date()` reclassified reads as sensor reads on a starved runner and the test waited for an emission that never came — frozen clock, except in the single test whose thesis is expiry.

The same class walks in through the constructor door: a clock parameter with a **production default** (`ContinuousSleepClock`) left blank at a test site is a wall clock injected without anyone ever writing `Date()`. Every test that constructs a clock-bearing type injects **all** of its clocks, including the one that will never advance — the suppressor's `readClock` stands still because the test double's reads are instantaneous, and it is precisely because it stands still that the read deadline cannot be decided by the runner's CPU. Measured: with `readClock` on its default, a pre-read that missed the 2 s of wall time suspends the domain with **readTimedOut** before the write starts, and the WRITE-deadline test still goes green, for the wrong reason.

## A negative claim is proven by a barrier, never by yield counting

"The consumer did not act" needs a POSITIVE signal that it has already passed the point — a sentinel emitted BEHIND what is being denied, on the same ordered stream, awaited by the bounded helper — otherwise the scheduler-slot budget runs out before the consumer ever runs and the test passes by never having looked (`MediaKeyHUDRouterTests.volumeKeysAreNotRouted`; one sentinel per channel, so that each channel's final count is assertive rather than transient).

The negative wait that gives something-that-must-not-happen its chance **does not use the 5 s budget**: it is a SHORT wall-clock window that returns the instant the footprint appears (`footprintAppears`, in `ChainedNowPlayingSourceTests`) — the long budget exists so a positive wait does not expire early, and in a negative one expiring early can only pass wrongly, never fail wrongly.

**A loop that hammers until the answer arrives leaves work of its own in the queue — and an `advance()` after it kills the wrong target**: `eventually { press; return !consumed }` proves the fact arrived, never that it SETTLED; each press before the answer enqueues one more apply on the chain, which drains after the loop, and the following advance expires THAT apply's deadline (a legitimate swallowed-key suspension) instead of what the test was measuring — failing at the assertion that exists to rule that suspension out (measured: green in isolation, 2/2 red in the parallel suite). The right barrier is an END-OF-WORK signal, not fact-arrival: an apply from another domain enqueued behind it (the chain is a single one) awaited via `onApplied` proves that everything before it finished and that the read clock is left with no sleeper.

**Every `advance()` on a test clock is preceded by `waitForSleep()`** — an advance before the park is a no-op, and a no-op in a timeout test leaves everything green for the wrong reason (`AbsentCapabilityHandbackTests`).

**Mutating test-double state behind an in-flight read demands the same positive barrier**: the brightness `sample()` returns BEFORE the read runs on the channel's serial queue — `waitForSleep` barriers the poll, never that read — so `value` only changes after the fake's `readCount` confirms the return (the rule lives in `FakeBrightnessBackend`'s own doc). Measured in CI: on a starved runner the key's read slid past the script's next step and emitted as a keypress the 0.8 that belonged to the sensor (2026-07-31, reproduced locally with a delay probe and killed by the barrier in the three tests of that shape).

## An accessor that wraps a non-optional requirement never returns nil

A presence assertion on it (`!= nil`, a nil×nil partition) is a tautology that survives every present and future case — what bites is comparing the VALUE against the case's concrete rule, from a table written independently of the production switch (`FixedWindowFrameTests`).

## CI runs the suite serial, and the verdict is a line

`-parallel-testing-enabled NO`, there only: 3 vCPU / 7 GB (macos-15 arm64) cannot carry 115 parallel suites — the GCD global pool has a per-QoS ceiling, the tests that model hangs park real threads in it by design, and an apply's pre-read sat in the queue for 75 s with the write never starting.

The job is ruled by the `Test run with N tests` line via a watchdog in `ci.yml`: the host teardown hangs with everything green, so the line is the verdict, never xcodebuild's exit. **Absence of a verdict is always failure**, including when xcodebuild exits 0 — a run that never reported is a run whose result nobody has, and deferring to its exit would invert the very rule (measured: the step went green). Since the step's shell is `bash -e`, the no-verdict branch's `wait` captures the status with `|| status=$?` — the raw `wait; status=$?` aborted the step BEFORE the diagnostic that branch exists to print.

Locally, concurrent `xcodebuild test` runs fight over the build-system lock in the shared DerivedData (it looks like a deadlock) — for parallel runs, use an isolated `-derivedDataPath`.

## What is unit, what is not

**Unit** (runs without touching a system API):

- Coordinator: state transitions, HUD priority over now playing, timer revert, hover — always with mocked sources.
- Each style's frame rule with a fake `ScreenGeometry` — including the notch geometry (with and without the slit).
- Decoding and mapping the OSD notification (JSON) → `SystemHUD`.
- The now-playing fallback chain, with availability driven by the mocks (adapter ok / JXA only / none).
- Graceful degradation: an absent external integration does not affect the essential flows.

**Not unit** (thin edge; manual/smoke validation): the real adapter process, Core Audio, the event tap, OSDUIHelper, the real `DistributedNotificationCenter`. The rule is to keep those edges thin enough that all the interesting logic lives above them — and is testable.

Minimum focus (living checklist):

- [ ] Coordinator: state transitions, HUD priority, timer revert (with mocked sources, without touching a system API)
- [ ] Window rules (`windowFrame`) per style, including the notch computation
- [ ] Now-playing fallback when the adapter is unavailable
- [ ] Integration source: decode the OSD notification and map it to the correct `SystemHUD`; the app works normally when the integration is absent (graceful degradation)
