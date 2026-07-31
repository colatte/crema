import Testing
@testable import Crema

/// The read-side sibling of the write's deadline (docs/DECISIONS.md:
/// read-deadline-pool-rule). Every blocking C read on the apply path — the
/// pre-read, the read-back, the mute-plane reads,
/// the volume IPC guards — and the recovery probe's reads race the apply
/// deadline on a detached task, so a stalled read (a coreaudiod hang) suspends
/// the domain instead of freezing the whole MainActor and wedging the apply
/// queue. A read that completes late is pure: its result is dropped by the
/// single-resume guard, writing nothing.
///
/// Every test here runs on the MainActor. A read that blocked the actor inline
/// would freeze the test itself — so the fact that each test makes progress
/// (advances a clock, evaluates an expectation) is the standing proof that the
/// blocked read is off the actor. The doubles' hung reads park a real detached
/// thread on a semaphore; each test releases them so the orphan frees.
@MainActor
struct OSDSuppressionReadDeadlineTests {

    // MARK: - Apply-path reads: a stall suspends the domain, never freezes

    @Test func aHungPreReadHitsTheReadDeadlineAndSuspends() async {
        let h = OSDSuppressorHarness()
        h.screen.readHangs = true   // the pre-read blocks on a detached thread
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        // The MainActor is free — the test drives the fake read clock to expiry.
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.screenBrightness)
        })
        #expect(h.suppressor.isEngaged)        // domain-scoped, engagement stays on
        #expect(h.screen.applied.isEmpty)      // never reached the write

        h.screen.releaseRead()                 // free the orphaned read
        await settle()
    }

    @Test func aHungReadBackHitsTheReadDeadlineAndSuspends() async {
        let h = OSDSuppressorHarness()
        h.screen.readHangs = true
        h.screen.passReadsBeforeHang = 1   // the pre-read passes; the read-back stalls
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        // The fast pre-read races its own deadline across a GCD hop: advancing
        // the read clock before the write lands can fire THAT deadline and
        // suspend without the write ever running. The landed write is the
        // proof the pre-read won; only then drive the hung read-back's
        // deadline (the pre-read's cancelled sleeper is already gone).
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.screenBrightness)
        })
        #expect(h.suppressor.isEngaged)

        h.screen.releaseRead()
        await settle()
    }

    @Test func aHungReadMutedInTheMutePlanSuspendsTheVolumeDomain() async {
        let h = OSDSuppressorHarness()
        h.volume.readMutedHangs = true   // the mute-plane read stalls
        h.suppressor.setEngaged(true)

        h.keys.press(.mute)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.volume)
        })
        #expect(h.suppressor.isEngaged)
        #expect(h.volume.mutedWrites.isEmpty)   // never reached the mute write

        h.volume.releaseHang()
        await settle()
    }

    @Test func aHungVolumeAvailabilityGuardSuspendsTheVolumeDomain() async {
        // The volume guards are Core Audio IPC (defaultOutputDeviceID), not a
        // pure nil-check like brightness — so they race the deadline too.
        let h = OSDSuppressorHarness()
        h.volume.availableHangs = true   // the isAvailable() guard stalls
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.volume)
        })
        #expect(h.suppressor.isEngaged)
        #expect(h.volume.applied.isEmpty)   // never reached the step write

        h.volume.releaseHang()
        await settle()
    }

    @Test func aHungSupportsMuteGuardSuspendsTheVolumeDomain() async {
        // supportsMute() is AudioObjectHasProperty — Core Audio IPC that can
        // stall like the reads, so the mute plan races it against the deadline
        // before ever reading the mute state. A hung capability guard must
        // suspend the domain, not freeze the MainActor.
        let h = OSDSuppressorHarness()
        h.volume.supportsMuteHangs = true   // the mute-capability guard stalls
        h.suppressor.setEngaged(true)

        h.keys.press(.mute)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.volume)
        })
        #expect(h.suppressor.isEngaged)
        #expect(h.volume.mutedWrites.isEmpty)   // never reached the mute write

        h.volume.releaseHang()
        await settle()
    }

    @Test func aHungReadMutedInVolumeUpUnmuteFirstSuspendsTheVolumeDomain() async {
        // volumeUp unmutes first when the device is muted (like the native
        // handler); that mute-plane read is Core Audio IPC and races the deadline
        // too — the unmute-first branch, distinct from the .mute plan covered
        // above. A stall there must suspend the domain, never leave the user
        // pressing a silent volume key.
        let h = OSDSuppressorHarness()
        h.volume.muted = true            // volumeUp takes the unmute-first branch
        h.volume.readMutedHangs = true   // its mute read stalls before the step
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.volume)
        })
        #expect(h.suppressor.isEngaged)
        #expect(h.volume.applied.isEmpty)       // never reached the volume step
        #expect(h.volume.mutedWrites.isEmpty)   // never reached the unmute write

        h.volume.releaseHang()
        await settle()
    }

    @Test func aHungKeyboardAvailabilityGuardSuspendsItsDomain() async {
        // The one availability guard on the brightness side that really is IPC:
        // CoreBrightness answers it by enumerating the backlight IDs over the
        // private client's connection, and it is re-asked per press precisely
        // because a cold boot can answer "no keyboard" before the service is up.
        // Its screen sibling is two dlsym results resolved at init and cannot
        // block, which is why only this one races a deadline. Inline, this froze
        // the MainActor once per backlight key.
        let h = OSDSuppressorHarness()
        h.keyboard.availableHangs = true
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.keyboardBrightness)
        })
        #expect(h.suppressor.isEngaged)          // domain-scoped, engagement stays on
        #expect(h.keyboard.applied.isEmpty)      // never reached the write
        // A stall is not an answer, so it must not be read as "no such control":
        // that verdict hands the key back with no probe and no way home.
        #expect(h.suppressor.suspendedDomains.contains(.keyboardBrightness))

        h.keyboard.releaseAvailable()
        await settle()
    }

    // MARK: - Probe-loop read: expires without freezing, the loop continues

    @Test func aHungProbeReadExpiresWithoutFreezingThenRecovers() async {
        let h = OSDSuppressorHarness()
        h.screen.value = nil   // a fast failure enters the suspension (no hang yet)
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.screenBrightness) })
        await h.clock.waitForSleep()   // the recovery probe is parked on the backoff

        // Make the probe's read hang, then run the probe.
        h.screen.readHangs = true
        h.clock.advance()

        // The hung probe read hits the read deadline and is treated as a present-
        // channel failure; the loop must NOT freeze — it parks its next backoff.
        #expect(await eventually {
            h.readClock.advance()
            return h.clock.pendingSleeps == 1
        })
        #expect(h.suppressor.suspendedDomains.contains(.screenBrightness))   // still suspended
        #expect(h.suppressor.longSuspendedDomains.isEmpty)                   // one failure, not escalated

        // The channel heals; releasing the orphaned read and running the next
        // probe recovers the domain — proof the loop is still alive.
        h.screen.readHangs = false
        h.screen.value = 0.5
        h.screen.releaseRead()
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.screenBrightness)
        })
    }

    @Test func aHungKeyboardAvailabilityGuardInTheProbeExpiresWithoutFreezing() async {
        // The probe asks availability before the read, to tell a genuinely absent
        // channel from a present one that cannot be read. On the keyboard that
        // question is the same stalling IPC the apply path races, and it runs on
        // every backoff cycle — inline, it blocked the MainActor once per cycle,
        // for as long as the domain stayed suspended.
        let h = OSDSuppressorHarness()
        h.keyboard.value = nil   // a fast failure enters the suspension (no hang yet)
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.keyboardBrightness) })
        await h.clock.waitForSleep()   // the recovery probe is parked on the backoff

        h.keyboard.availableHangs = true
        h.clock.advance()

        // The loop must park its next backoff rather than freeze on the guard.
        #expect(await eventually {
            h.readClock.advance()
            return h.clock.pendingSleeps == 1
        })
        #expect(h.suppressor.suspendedDomains.contains(.keyboardBrightness))
        #expect(h.suppressor.longSuspendedDomains.isEmpty)   // one failure, not escalated

        // The service answers again; the next probe recovers — proof the loop lived.
        h.keyboard.availableHangs = false
        h.keyboard.value = 0.5
        h.keyboard.releaseAvailable()
        #expect(await eventually {
            h.clock.advance()
            return !h.suppressor.suspendedDomains.contains(.keyboardBrightness)
        })
    }

    // MARK: - Late-completing orphan writes no zombie state

    @Test func aLateCompletingReadWritesNoZombieState() async {
        // The abandoned read returns long after the deadline suspended the
        // domain. It must apply nothing, fire no onApplied, and not un-suspend:
        // its result is dropped by the single-resume guard.
        let h = OSDSuppressorHarness()
        let applied = CounterBox()
        h.suppressor.onApplied = { [applied] _ in applied.count += 1 }
        h.screen.readHangs = true   // the pre-read stalls past the deadline
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually {
            h.readClock.advance()
            return h.suppressor.suspendedDomains.contains(.screenBrightness)
        })

        h.screen.releaseRead()   // the stalled read finally returns, late
        await settle()

        #expect(h.screen.applied.isEmpty)   // never reached the write
        // Box.count is a running counter, not a collection.
        // swiftlint:disable:next empty_count
        #expect(applied.count == 0)          // no onApplied from the abandoned read
        #expect(h.suppressor.suspendedDomains.contains(.screenBrightness))   // still suspended
    }

    // MARK: - Happy path is intact

    @Test func fastReadsRaceTheDeadlineAndWinApplyingAsBefore() async {
        // The deadline machinery is transparent when reads return promptly: the
        // read wins the race, the deadline sleep is cancelled, the apply lands
        // exactly as it did before the read was raced.
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })

        h.keys.press(.screenBrightnessUp)
        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })

        #expect(h.suppressor.suspendedDomains.isEmpty)   // no false suspension
        #expect(h.suppressor.isEngaged)
    }
}
