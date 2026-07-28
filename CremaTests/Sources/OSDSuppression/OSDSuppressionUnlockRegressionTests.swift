import Testing
@testable import Crema

/// Regression hunt for the reported symptom: after a lock / display-sleep +
/// unlock cycle, a brightness key shows the native OSD "permanently" and the
/// domain never re-engages on its own (minutes, many keys). This file drives the
/// production suppressor at the seam (mocked channels + a captured consumer +
/// separate backoff/read clocks) through the interleavings the orchestrator
/// flagged, so a wedge surfaces as a bounded assertion failure — never a hung
/// suite (waitForSleep/eventually are all capped).
///
/// Naming: `MUST_PASS_` marks the Round-1 happy paths that pin correct behavior;
/// `HUNT_` marks the wedge probes.
@MainActor
struct OSDSuppressionUnlockRegressionTests {

    // The lock/unlock harness (OSDSuppressorLockHarness, CremaTests/Mocks/)
    // owns the real SuppressionLockController over a mock lock source, so these
    // suites exercise the actual engage/disengage policy the report goes
    // through — not a bare setEngaged.

    // MARK: - V1 · MUST PASS: read-nil suspension self-heals when the read heals

    @Test func MUST_PASS_readNilSuspensionSelfHealsWhenReadRecovers() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil            // reads fail post-wake → currentValueUnreadable
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        h.screen.value = 0.5            // the display finished waking; reads recover
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.screenBrightness)
        })
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
    }

    // MARK: - V4 · MUST PASS: the reported cycle, screen brightness path

    // lock (display sleep) -> unlock -> read fails at wake -> suspend ->
    // read recovers -> probe re-engages. Screen uses a per-operation display ID,
    // so its read heals post-wake; this pins that the seam recovers.

    @Test func MUST_PASS_lockUnlockThenReadNilSuspendThenHealReengages() async {
        let h = OSDSuppressorLockHarness()
        #expect(h.suppressor.isEngaged)              // safe + opted-in

        h.lock.set(safe: false)                      // screen locks / display sleeps
        #expect(await eventually { !h.suppressor.isEngaged })

        h.lock.set(safe: true)                       // unlock
        #expect(await eventually { h.suppressor.isEngaged })

        // At wake the display is not ready: reads fail, the first key suspends.
        h.screen.value = nil
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // The display finishes waking; the recovery probe must re-engage it.
        h.screen.value = 0.5
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.screenBrightness)
        })
        #expect(h.suppressor.isEngaged)
    }

    // MARK: - V2 · the cravado regression (hypothesis a): read-OK/write-dead

    // The reported symptom's mechanism. The write-dead channel: apply "succeeds"
    // (records) but the value never moves, so the read-back verification fails
    // and the domain suspends — yet
    // the recovery probe only reads, and the read returns a value, so it
    // re-engages a channel that still cannot apply. Pre-fix this flapped
    // suspend/re-engage forever and never escalated (each read-only re-engage
    // discarded the escalation counter), so the user saw the native OSD
    // "permanently" on brightness with no stable signal. The fix adds a
    // write-health escalation axis (unconfirmedApplyFailures) that survives the
    // optimistic re-engage and is reset only by a verified apply, so a
    // persistently un-appliable channel surfaces in the menu. This pins that
    // fixed outcome (pre-fix it failed at the final expect).
    @Test func writeDeadReadOKChannelEscalatesToTheMenuInsteadOfFlappingForever() async {
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true     // write records but never moves; read stays OK
        h.suppressor.setEngaged(true)

        // Realistic use: the user keeps pressing the (broken) brightness key.
        // Each press either flows through+kicks (while suspended) or is
        // swallowed+fails+suspends (while engaged) — the flap.
        var reengagedAfterFailure = 0
        for _ in 0..<(OSDTest.escalation * 4) {
            h.keys.press(.screenBrightnessUp)
            // let the apply land and possibly suspend
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            // advance whatever recovery probe is parked and let it re-engage
            let reengaged = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
            if reengaged { reengagedAfterFailure += 1 }
        }

        // The value never actually moved (write is dead) …
        #expect(h.screen.value == 0.5)
        // … the read-only probe still optimistically re-engaged the un-appliable
        // channel (the flap is inherent to a read-only probe) …
        #expect(reengagedAfterFailure > 0)
        // … but the write-health axis escalated it, so the user gets a stable
        // signal that the channel is broken instead of a silent native-OSD-only
        // brightness key forever. This is the pin the regression violated.
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness),
                "a persistently un-appliable channel must surface in the menu, not flap in silence")
    }

    // MARK: - V2b · the menu warning is stable once a write-dead channel escalates

    // It must not flicker off on each read-only re-engage.
    // The failure mode this guards: escalate on the flap axis, then let a
    // read-only probe re-engage and CLEAR the warning, so the menu blinks on and
    // off every cycle. The fix keeps the warning up across an optimistic
    // re-engage (only a verified apply may clear it), so once surfaced it stays
    // surfaced while the write stays dead — and onSuspensionStateChange fires
    // exactly once for the escalation, not once per flap.
    @Test func writeDeadEscalationStaysSurfacedAndDoesNotChurnTheMenu() async {
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true
        h.suppressor.setEngaged(true)

        // Drive it well past the threshold, sampling the warning while the domain
        // is momentarily re-engaged (the state where a flicker would show).
        for _ in 0..<(OSDTest.escalation * 3) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
        }

        // Escalated and, crucially, still surfaced while re-engaged.
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness))
        #expect(!h.suppressor.suspendedDomains.contains(.screenBrightness))   // momentarily re-engaged
        // The menu was told exactly once (one escalation), never a per-flap churn.
        #expect(h.suspensionChanges == 1,
                "the menu warning flickered on each read-only re-engage instead of staying stable")
    }

    // MARK: - V2c · a write-dead channel that heals recovers genuinely

    // The first VERIFIED apply after the write comes back clears the warning and
    // the flap axis. This is the field scenario (the wake ramp settles in
    // seconds), and proves the fix does not strand the domain long-suspended
    // forever.

    @Test func writeDeadChannelHealsOnTheFirstVerifiedApplyAfterTheWriteReturns() async {
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true
        h.suppressor.setEngaged(true)

        // Flap it to the menu warning.
        for _ in 0..<(OSDTest.escalation + 1) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })

        // The display finishes waking: the write path comes alive. The domain is
        // momentarily re-engaged (read-only probe), so the next consumed key runs
        // a real apply — which now verifies. That verified apply is the genuine
        // recovery: it clears the flap axis and the menu warning.
        h.screen.writeIsDead = false
        #expect(await eventually {
            h.clock.advance()                          // let any parked probe re-engage
            if !h.suppressor.suspendedDomains.contains(.screenBrightness) {
                h.keys.press(.screenBrightnessUp)      // a real apply on the healed write
            }
            return h.suppressor.longSuspendedDomains.isEmpty
        }, "a genuinely healed write never cleared the menu warning")
        #expect(!h.suppressor.suspendedDomains.contains(.screenBrightness))
        #expect(h.suppressor.isEngaged)
        #expect(h.screen.applied.last == h.screen.value)   // the write finally moved the value
    }

    // MARK: - V3 · HUNT (priority e): burst kicks against the async probe

    // Hammer immediate-probe kicks while the recovery probe's read is genuinely
    // async (parked on a real GCD hop / read-deadline), interleaved with backoff
    // and read-clock advances, then heal — the domain MUST recover. A cancel/
    // restart hole that leaves the loop dead with the probeImmediately flag stuck
    // (so future kicks coalesce to no-ops) would wedge here, and the bounded
    // eventually turns that into a failure.
    @Test func HUNT_burstKicksAgainstAsyncProbeStillRecover() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        await h.clock.waitForSleep()          // the scheduled probe is parked

        // Make probe reads hang so probeOutcome is genuinely suspended, then fire
        // a burst of kicks that each cancel+restart the loop mid-await.
        h.screen.readHangs = true
        for _ in 0..<8 {
            h.keys.press(.screenBrightnessUp)  // kick: cancel+restart the probe loop
            await settle()
            h.readClock.advance()              // let a hung probe read hit its deadline
            await settle()
        }

        // Heal everything and drain the orphaned reads; the loop must still be
        // alive to recover the domain.
        h.screen.readHangs = false
        h.screen.value = 0.5
        for _ in 0..<16 { h.screen.releaseRead() }   // free any parked orphan reads
        #expect(await eventually {
            h.clock.advance()
            h.readClock.advance()
            h.keys.press(.screenBrightnessUp)         // also try a kick-driven recovery
            return !h.suppressor.suspendedDomains.contains(.screenBrightness)
        }, "burst kicks against the async probe wedged the recovery loop")
        for _ in 0..<16 { h.screen.releaseRead() }
        await settle()
    }

    // MARK: - V5 · HUNT (hypothesis f/5): probe read deadline expiring for

    // several cycles, then healing — must recover.

    @Test func HUNT_probeReadDeadlineExpiresRepeatedlyThenRecovers() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        h.screen.readHangs = true
        // Several backoff cycles where the probe read hangs and hits the read
        // deadline (failedChannelPresent) — the loop must keep parking the next
        // backoff, never freeze.
        for _ in 0..<(OSDTest.escalation + 2) {
            await h.clock.waitForSleep()
            h.clock.advance()                    // wake the probe → its read hangs
            #expect(await eventually {
                h.readClock.advance()            // read hits its deadline
                return h.clock.pendingSleeps == 1 // loop parked the next backoff
            })
        }
        #expect(h.suppressor.suspendedDomains.contains(.screenBrightness))

        // Heal: releasing the orphans + a live read recovers the domain.
        h.screen.readHangs = false
        h.screen.value = 0.5
        for _ in 0..<32 { h.screen.releaseRead() }
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.screenBrightness)
        }, "the probe loop died across repeated read-deadline expirations")
        for _ in 0..<32 { h.screen.releaseRead() }
        await settle()
    }

    // MARK: - V6 · HUNT (hypothesis c/e): lock edge landing on a suspended,

    // long-suspended domain, then unlock — the re-engage must be born healthy.

    @Test func HUNT_lockWhileLongSuspendedThenUnlockRecovers() async {
        let h = OSDSuppressorLockHarness()
        h.screen.value = nil
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Drive it to long-suspended (menu warning).
        for _ in 0..<OSDTest.escalation {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })

        // Lock while long-suspended: disengage must clear every per-domain state.
        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.suppressor.suspendedDomains.isEmpty)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)

        // Unlock with the channel healed: born fully healthy, keys apply again.
        h.screen.value = 0.5
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        #expect(h.suppressor.suspendedDomains.isEmpty)
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
    }

    // MARK: - V2d · the retry button clears a latched write-dead warning

    // corretude-1: once a write-dead channel escalates and the read-only probe
    // re-engages it, the domain is no longer suspended but its menu warning stays
    // latched (writeStillUnconfirmed). retrySuspendedNow's suspended-only loop
    // could not reach it, so the "Try to reactivate now" button was a dead no-op
    // in exactly this state — and a warning left stale by a silently-healed write
    // (the user stopped pressing, so no verified apply ever cleared it) could
    // never be dismissed. The button now clears the latch for a re-engaged
    // long-suspended domain.
    @Test func retryClearsALatchedWriteDeadWarningOnAReengagedDomain() async {
        let h = OSDSuppressorHarness()
        h.screen.writeIsDead = true
        h.suppressor.setEngaged(true)

        for _ in 0..<(OSDTest.escalation * 3) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
        }
        // Escalated to the menu and momentarily re-engaged — the exact state the
        // suspended-only retry loop skipped.
        #expect(h.suppressor.longSuspendedDomains.contains(.screenBrightness))
        #expect(!h.suppressor.suspendedDomains.contains(.screenBrightness))

        // The user clicks "Try to reactivate now": the latch clears and the menu
        // warning goes away (pre-fix the button did nothing in this state).
        h.suppressor.retrySuspendedNow()
        #expect(h.suppressor.longSuspendedDomains.isEmpty,
                "the retry button left a re-engaged domain's menu warning stuck")
    }

    // MARK: - V7 · MUST PASS: write-dead escalation through the real lock cycle

    // The write-health axis is born healthy again after the disengage.
    // design-testes-2: the cravado write-dead regression driven through the real
    // SuppressionLockController (lock → unlock), not a bare setEngaged; plus a pin
    // on the disengage clearing the write-health axis. With the axis carried over,
    // the first flap after unlock would re-escalate instantly instead of taking a
    // fresh full run — so this catches a removal of the engage/disengage reset.
    @Test func MUST_PASS_writeDeadEscalationThroughLockResetsTheWriteAxis() async {
        let h = OSDSuppressorLockHarness()
        #expect(h.suppressor.isEngaged)              // safe + opted-in

        h.screen.writeIsDead = true                  // write records but never moves
        for _ in 0..<(OSDTest.escalation * 3) {
            h.keys.press(.screenBrightnessUp)
            _ = await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) }
            _ = await eventually {
                h.clock.advance()
                return !h.suppressor.suspendedDomains.contains(.screenBrightness)
            }
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })

        // Lock (display sleep): the disengage clears every per-domain state,
        // including the write-health axis.
        h.lock.set(safe: false)
        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
        #expect(h.suppressor.suspendedDomains.isEmpty)

        // Unlock with the write STILL dead: the re-engage must be born healthy, so
        // the first flap suspends but does NOT re-escalate — the escalated count
        // did not survive the disengage.
        h.lock.set(safe: true)
        #expect(await eventually { h.suppressor.isEngaged })
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        await settle()
        #expect(h.suppressor.longSuspendedDomains.isEmpty,
                "the write-health axis carried its escalated count across a disengage")
    }
}
