import Testing
@testable import Crema

/// Per-domain suspension (docs/DECISIONS.md: per-domain-suspension): an apply
/// failure suspends only its own domain (volume, screen brightness, keyboard
/// brightness) with the native OSD restored for it, a read-only probe self-heals
/// it on recovery, and a channel that stays broken with its device present
/// escalates to the menu. No global disengage, ever.
@MainActor
struct OSDSuppressionDomainSuspensionTests {

    // MARK: - #1: an isolated failure self-heals

    @Test func anIsolatedFailureSuspendsThenAProbeReengagesTheDomain() async {
        let h = OSDSuppressorHarness()
        h.volume.value = nil   // reads fail → currentValueUnreadable, no deadline
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        #expect(h.suppressor.isEngaged)   // only the domain suspended, not the engagement

        // The channel recovers; the next probe re-engages it silently.
        h.volume.value = 0.5
        await h.clock.waitForSleep()      // probe parked on the backoff
        h.clock.advance()
        #expect(await eventually { !h.suppressor.suspendedDomains.contains(.volume) })

        // Keys are consumed and applied again.
        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })
        #expect(h.suppressor.longSuspendedDomains.isEmpty)   // never escalated
        #expect(h.suspensionChanges == 0)                    // transient: no menu churn
    }

    // MARK: - #2: per-domain radius

    @Test func aDeadBrightnessChannelSuspendsOnlyBrightnessNotVolume() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Volume keeps being consumed and applied — the old bug, before
        // per-domain suspension, was a brightness failure killing volume
        // suppression too.
        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })
        #expect(h.suppressor.isEngaged)
        #expect(!h.suppressor.suspendedDomains.contains(.volume))
    }

    @Test func aDeadVolumeChannelSuspendsOnlyVolumeNotBrightness() async {
        let h = OSDSuppressorHarness()
        h.volume.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
        #expect(!h.suppressor.suspendedDomains.contains(.screenBrightness))
    }

    // MARK: - #4: pass-through is consistent across both phases

    @Test func aSuspendedDomainPassesBothPhasesWhileOthersStaySwallowed() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Screen keys pass through on BOTH phases (a swallowed down + leaked up
        // would orphan the pair in the system).
        #expect(h.keys.pressDown(.screenBrightnessUp) == false)
        #expect(h.keys.pressUp(.screenBrightnessUp) == false)
        #expect(h.keys.pressDown(.screenBrightnessDown) == false)
        #expect(h.keys.pressUp(.screenBrightnessDown) == false)

        // The other domains keep swallowing both phases.
        #expect(h.keys.pressDown(.volumeUp) == true)
        #expect(h.keys.pressUp(.volumeUp) == true)
        #expect(h.keys.pressDown(.keyboardBrightnessUp) == true)
        #expect(h.keys.pressUp(.keyboardBrightnessUp) == true)
    }

    @Test func muteFollowsTheVolumeDomainWhenVolumeIsSuspended() async {
        let h = OSDSuppressorHarness()
        h.volume.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })

        // Mute belongs to the volume domain, so it passes through too.
        #expect(h.keys.pressDown(.mute) == false)
        #expect(h.keys.pressUp(.mute) == false)
    }

    // MARK: - VIGA 2 / consumer contract: a key press alone kicks recovery

    @Test func aKeyPressOnASuspendedButHealedDomainReengagesWithoutTheBackoff() async {
        // The consumer contract's second half: a key pressed on a suspended
        // domain passes through AND kicks an immediate recovery probe, so an
        // active user heals ahead of the backoff. Here recovery comes only from
        // the press — the clock is never advanced, so a missing kick would leave
        // the domain parked on the backoff forever.
        let h = OSDSuppressorHarness()
        h.volume.value = nil   // reads fail → suspends the volume domain
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        await h.clock.waitForSleep()   // the recovery probe is parked on the backoff

        // The channel heals; pressing the key kicks the parked probe to run now.
        h.volume.value = 0.5
        h.keys.press(.volumeUp)
        #expect(await eventually { !h.suppressor.suspendedDomains.contains(.volume) })
        #expect(h.suppressor.isEngaged)
        #expect(h.suspensionChanges == 0)   // transient recovery, no menu churn
    }

    // MARK: - #5: device-absent probes never escalate (AirPods swap by design)

    @Test func deviceAbsentProbesNeverEscalateAndReengageWhenItReturns() async {
        // The AirPods swap: the real trigger is a noOutputDevice throw mid-write;
        // here reads fail to enter the suspension, then the device goes absent so
        // every probe reports channel-absent — which must never escalate.
        let h = OSDSuppressorHarness()
        h.volume.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })

        h.volume.available = false   // output device gone
        for _ in 0..<(OSDTest.escalation + 3) {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(h.suppressor.longSuspendedDomains.isEmpty)          // never escalated
        #expect(h.suppressor.suspendedDomains.contains(.volume))    // still suspended, quietly
        #expect(h.suspensionChanges == 0)

        // The device returns → the next probe re-engages. The pending probe
        // turn may be in either place depending on how the loop's handshake
        // aligned: already advanced (runs on the next yield) or still parked
        // on the backoff. Advancing whatever is parked while yielding covers
        // both — a fixed waitForSleep/advance pair here deadlocks in the
        // already-advanced alignment, because the recovered probe loop ends
        // without ever parking again.
        h.volume.available = true
        h.volume.value = 0.5
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.volume)
        })
    }

    // MARK: - #6: escalation to the menu, and recovery

    @Test func fiveChannelPresentFailuresEscalateThenManualRetryHeals() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil   // reads fail, but the channel is present (available)
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.longSuspendedDomains.isEmpty)   // not escalated yet

        for _ in 0..<OSDTest.escalation {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })
        #expect(h.suspensionChanges >= 1)   // the menu callback fired

        // The menu's "try to reactivate now" with the channel healed → recovers.
        h.screen.value = 0.5
        h.suppressor.retrySuspendedNow()
        #expect(await eventually { !h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.longSuspendedDomains.isEmpty)   // flag cleared
    }

    @Test func recoveryResetsTheEscalationCounter() async {
        // A recovered domain that fails again must take another full five
        // failures to escalate — the counter is discarded on recovery, not
        // carried over.
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        for _ in 0..<OSDTest.escalation {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })

        // Heal it.
        h.screen.value = 0.5
        h.suppressor.retrySuspendedNow()
        #expect(await eventually { !h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Break it again; four failures must NOT escalate (counter restarted).
        h.screen.value = nil
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        for _ in 0..<(OSDTest.escalation - 1) {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        await settle()
        #expect(!h.suppressor.longSuspendedDomains.contains(.screenBrightness))

        // The fifth escalates.
        await h.clock.waitForSleep()
        h.clock.advance()
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })
    }

    @Test func keyKickedProbesNeverEscalateAPresentDeadChannel() async {
        // Escalation counts *scheduled* backoff probes only. A key press on a
        // suspended domain kicks an immediate probe; hammering a present-but-
        // dead key must not drive the counter to the menu warning below the
        // ~31 s backoff window. The clock is never advanced, so only key-kicked
        // immediate probes ever run.
        let h = OSDSuppressorHarness()
        h.screen.value = nil   // present (available) but unreadable → stays dead
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        await h.clock.waitForSleep()   // the scheduled recovery probe is parked

        // Hammer the dead key well past the escalation threshold.
        for _ in 0..<(OSDTest.escalation * 3) {
            h.keys.press(.screenBrightnessUp)
            await settle()
        }
        #expect(h.suppressor.longSuspendedDomains.isEmpty)                  // kicks never escalate
        #expect(h.suppressor.suspendedDomains.contains(.screenBrightness))  // still suspended, quietly
        #expect(h.suspensionChanges == 0)                                   // no menu churn
    }

    // MARK: - #7: disengage/engage clears per-domain state

    // The probe-loop generation guards (runProbeLoop's re-fetch guards) are
    // defensive back-stops for a rare zombie-probe race and are not directly
    // pinned here: a disengage cancels every probe (cancelAllProbes), so the
    // observable "disengage clears state" behavior is caught by cancellation,
    // not by the generation check. The residual race — a probe resuming after a
    // re-engage re-suspended the same domain — is further back-stopped by
    // reengage's own generation guard, and cannot be reproduced deterministically
    // with the fake clock (cancellation removes the parked sleeper).

    @Test func disengageCancelsProbesAndClearsSuspensionReengageIsHealthy() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Disengage (a lock edge or toggle-off) clears every per-domain state.
        h.suppressor.setEngaged(false)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)

        // Re-engage is born fully healthy, like a relaunch: the channel now
        // reads, so a key is consumed and applied.
        h.screen.value = 0.5
        h.suppressor.setEngaged(true)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
    }

    @Test func longSuspendedFlagClearsAcrossADisengage() async {
        // A disengage while a domain is long-suspended must clear the menu flag
        // and fire the change so the warning disappears.
        let h = OSDSuppressorHarness()
        h.screen.value = nil
        h.suppressor.setEngaged(true)
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        for _ in 0..<OSDTest.escalation {
            await h.clock.waitForSleep()
            h.clock.advance()
        }
        #expect(await eventually { h.suppressor.longSuspendedDomains.contains(.screenBrightness) })
        let before = h.suspensionChanges

        h.suppressor.setEngaged(false)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
        #expect(h.suspensionChanges == before + 1)
    }

    // MARK: - Failure-path suspension (each trigger suspends, none disengages)

    @Test func aThrowingApplySuspendsTheDomainNotTheEngagement() async {
        let h = OSDSuppressorHarness()
        h.screen.applyThrows = true
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.isEngaged)                            // engagement stays on
        #expect(h.keys.pressDown(.screenBrightnessUp) == false)   // that domain now passes through
    }

    @Test func aDeadWriteFailsTheSelfCheckAndSuspends() async {
        // The dangerous failure: the actuator accepts the write but nothing
        // moves — the read-back check catches it and suspends the domain.
        let h = OSDSuppressorHarness()
        h.volume.writeIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
    }

    @Test func aDeadMutePlaneOnVolumeUpSuspendsTheVolumeDomain() async {
        let h = OSDSuppressorHarness()
        h.volume.muted = true
        h.volume.muteWriteIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
    }

    @Test func anUnreadableCurrentValueSuspendsTheDomain() async {
        let h = OSDSuppressorHarness()
        h.keyboard.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.keyboardBrightness) })
    }

    @Test func aHungApplyHitsTheDeadlineAndSuspends() async {
        // The failure the read-back can't see: an apply that never completes
        // (coreaudiod stall). The deadline converts the hang into a domain
        // suspension and the native behavior comes back for it.
        let h = OSDSuppressorHarness()
        h.screen.applyHangs = true
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        await h.clock.waitForSleep(delay: OSDTest.deadline)
        h.clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(h.suppressor.isEngaged)
        #expect(h.screen.applied.isEmpty)   // the hung apply never landed
    }

    @Test func aBurstOfFailuresSuspendsOnceAndDropsTheQueue() async {
        let h = OSDSuppressorHarness()
        h.volume.writeIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)

        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })
        await settle()
        // One failure suspends; the queued keys fall through the suspension
        // guard, so only the first write ever reached the actuator.
        #expect(h.volume.applied.count == 1)
        #expect(h.suspensionChanges == 0)   // transient, no escalation
    }

    @Test func aChannelDyingMidRunSuspendsOnlyThatDomain() async {
        // The stale-display-ID signature at the suppressor seam: the channel
        // stays "available" yet its reads start failing mid-session. A consumed
        // key must surface that death — suspend that domain, never swallow the
        // key into a silent no-op. The radius is one domain: volume keeps
        // working while screen brightness suspends.
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied.count == 1 })   // healthy first

        h.screen.value = nil   // the display ID went stale: reads now fail
        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })

        // Volume is untouched by the brightness death.
        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })
        #expect(h.suppressor.isEngaged)
    }
}
