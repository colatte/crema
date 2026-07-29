import Testing
@testable import Crema

/// The production suppressor over mocked channels and a captured consumer:
/// stepping, ordering, mute, capability no-ops, the post-apply hook, the
/// generation guard, and the uncancellable-hang deadline. Per-domain
/// suspension and recovery live in OSDSuppressionDomainSuspensionTests;
/// the sacred-preference pins in OSDSuppressionPrefSacredTests.
@MainActor
struct MediaKeyInterceptionOSDSuppressorTests {

    // MARK: - Engage / consume basics

    @Test func engagingInstallsTheConsumerAndDisengagingRemovesIt() {
        let h = OSDSuppressorHarness()
        #expect(!h.keys.isConsuming)

        h.suppressor.setEngaged(true)
        #expect(h.suppressor.isEngaged)
        #expect(h.keys.isConsuming)

        // The reversibility story: nil consumer = pure observation again.
        h.suppressor.setEngaged(false)
        #expect(!h.suppressor.isEngaged)
        #expect(!h.keys.isConsuming)
    }

    @Test func volumeKeysStepByANativeSixteenthAndVerify() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })

        h.keys.press(.volumeDown)
        #expect(await eventually { h.volume.applied.count == 2 && h.volume.value == 0.5 })
        #expect(h.suppressor.isEngaged)   // verified applies keep it on
    }

    @Test func optionShiftStepsByAQuarterStep() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp, fine: true)

        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.fine] })
    }

    @Test func anAutorepeatBurstNeverLosesSteps() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)

        let step = OSDTest.step
        #expect(await eventually { h.volume.applied == [0.5 + step, 0.5 + 2 * step, 0.5 + 3 * step] })
    }

    @Test func mixedCoarseAndFineStepsBindPerKey() async {
        // The fine flag must ride each key through the chain — a sticky flag
        // would survive into the next press.
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp, fine: true)

        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step, 0.5 + OSDTest.step + OSDTest.fine] })
    }

    @Test func mutePressedInsideAVolumeBurstAppliesInOrder() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.mute)
        h.keys.press(.volumeUp)

        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step, 0.5 + 2 * OSDTest.step] })
        #expect(h.volume.mutedWrites == [true, false])   // mute on, then volume-up unmuted
        #expect(h.volume.muted == false)
    }

    @Test func muteTogglesBothWaysAndVerifies() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.mute)
        #expect(await eventually { h.volume.muted == true })

        h.keys.press(.mute)
        #expect(await eventually { h.volume.muted == false })
        #expect(h.volume.mutedWrites == [true, false])
        #expect(h.suppressor.isEngaged)
    }

    @Test func volumeUpUnmutesFirstLikeTheNativeHandler() async {
        let h = OSDSuppressorHarness()
        h.volume.muted = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.volume.muted == false && h.volume.applied.count == 1 })
    }

    @Test func brightnessKeysRouteToTheirChannels() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        h.keys.press(.keyboardBrightnessDown)

        #expect(await eventually { h.screen.applied == [0.5 + OSDTest.step] })
        #expect(await eventually { h.keyboard.applied == [0.5 - OSDTest.step] })
        #expect(h.volume.applied.isEmpty)
    }

    @Test func verifiedAppliesReportThroughOnApplied() async {
        // onApplied keeps firing for a healthy domain — this is what refreshes
        // the brightness HUD with the applied value.
        let h = OSDSuppressorHarness()
        let seen = CounterBox()
        h.suppressor.onApplied = { [seen] _ in seen.count += 1 }
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        h.keys.press(.volumeUp)

        #expect(await eventually { seen.count == 2 })
    }

    // MARK: - No-op boundaries and absent capabilities (never a suspension)

    @Test func aBoundaryStepIsANoOpNotASuspension() async {
        let h = OSDSuppressorHarness()
        h.volume.value = 1.0
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.volume.applied == [1.0] })
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }

    @Test func anAbsentCapabilityIsANoOpNeverASuspension() async {
        // HDMI/USB outputs without volume or mute, Macs without a keyboard
        // backlight: the native handler no-ops there (prohibited HUD), and
        // suspending would be wrong on ordinary hardware.
        let h = OSDSuppressorHarness()
        h.volume.available = false
        h.volume.muteSupported = false
        h.keyboard.available = false
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.mute)
        h.keys.press(.keyboardBrightnessUp)
        await settle()

        #expect(h.volume.applied.isEmpty)
        #expect(h.volume.mutedWrites.isEmpty)
        #expect(h.keyboard.applied.isEmpty)
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }

    @Test func aConsumedKeyOnAnUnavailableScreenChannelNoOpsWithoutSuspending() async {
        // A channel whose capability is genuinely absent (private symbols never
        // resolved) is a no-op like the native handler — never a suspension,
        // and never a silent swallow beyond the logged pass-through.
        let h = OSDSuppressorHarness()
        h.screen.available = false
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        h.keys.press(.screenBrightnessUp)
        await settle()

        #expect(h.screen.applied.isEmpty)
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }

    // MARK: - Uncancellable hang: deadline suspends, orphan lands cleanly

    @Test func aGenuinelyUncancellableHungWriteSuspendsWithinTheDeadline() async {
        // A write that never returns AND never observes cancellation (a blocked
        // C actuator call). The deadline must return and suspend regardless.
        let keys = MockMediaKeyConsuming()
        let hang = ControllableHangOSDChannel()
        let clock = TestSleepClock()
        let suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: MockOSDVolumeChannel(),
            screen: hang, keyboard: MockOSDChannel(), clock: clock
        )
        suppressor.setEngaged(true)

        keys.press(.screenBrightnessUp)
        await hang.waitForWriteStart()
        await clock.waitForSleep(delay: OSDTest.deadline)
        clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { suppressor.suspendedDomains.contains(.screenBrightness) })
        #expect(suppressor.isEngaged)                            // engagement stays on
        #expect(keys.pressDown(.screenBrightnessUp) == false)   // that domain passes through
        #expect(hang.applied.isEmpty)                           // the abandoned write never landed

        hang.release()   // let the orphan finish so its continuation is not leaked
        await settle()
    }

    @Test func anAbandonedWriteThatLandsLateAppliesNoZombieState() async {
        // The orphaned write finishes long after the deadline. It moves the
        // hardware value (the consumed press's own intent — the bounded
        // residual), but fires no onApplied and does not itself re-engage the
        // domain: recovery is the probe's job, not a late write's.
        let keys = MockMediaKeyConsuming()
        let hang = ControllableHangOSDChannel()
        let clock = TestSleepClock()
        let applied = CounterBox()
        let suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: MockOSDVolumeChannel(),
            screen: hang, keyboard: MockOSDChannel(), clock: clock
        )
        suppressor.onApplied = { [applied] _ in applied.count += 1 }
        suppressor.setEngaged(true)

        keys.press(.screenBrightnessUp)
        await hang.waitForWriteStart()
        await clock.waitForSleep(delay: OSDTest.deadline)
        clock.advance(delay: OSDTest.deadline)
        #expect(await eventually { suppressor.suspendedDomains.contains(.screenBrightness) })

        hang.release()   // the actuator finally returns, landing the write late
        await settle()

        #expect(hang.applied == [0.5 + OSDTest.step])   // value moved: the honest residual
        // Box.count is a running counter, not a collection.
        // swiftlint:disable:next empty_count
        #expect(applied.count == 0)                     // but no HUD/onApplied fired
        #expect(suppressor.suspendedDomains.contains(.screenBrightness))   // still suspended
    }

    @Test func aHungWriteBoundsOrphansToOneAndDropsTheQueuedKeys() async {
        // Orphan accumulation under a persistent stall is bounded by the queue
        // + suspension semantics: applies run strictly in order, so a second
        // write cannot start until the first returns; the first only returns at
        // the deadline (suspending the domain), after which the queued keys fall
        // through the suspension guard. Exactly one write is ever outstanding.
        let keys = MockMediaKeyConsuming()
        let hang = ControllableHangOSDChannel()
        let clock = TestSleepClock()
        let suppressor = MediaKeyInterceptionOSDSuppressor(
            keys: keys, volume: MockOSDVolumeChannel(),
            screen: hang, keyboard: MockOSDChannel(), clock: clock
        )
        suppressor.setEngaged(true)

        keys.press(.screenBrightnessUp)   // this one hangs
        await hang.waitForWriteStart()
        keys.press(.screenBrightnessUp)   // queued behind the hung apply
        keys.press(.screenBrightnessUp)
        await clock.waitForSleep(delay: OSDTest.deadline)
        clock.advance(delay: OSDTest.deadline)

        #expect(await eventually { suppressor.suspendedDomains.contains(.screenBrightness) })
        await settle()
        #expect(hang.writeStartCount == 1)   // only one actuator write ever started
        #expect(hang.applied.isEmpty)

        hang.release()   // let the single orphan finish so its continuation is not leaked
        await settle()
    }

    // MARK: - Generation guard (apply side)

    @Test func keysConsumedBeforeADisengageLandsDoNotApply() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        // The tap's consumer hops to the main actor: a disengage that runs
        // before the hop lands must drop the queued key.
        h.keys.press(.volumeUp)
        h.suppressor.setEngaged(false)

        await settle()
        #expect(h.volume.applied.isEmpty)
    }

    @Test func aStaleKeyFromABygoneEngagementNeverAppliesAfterAReengage() async {
        let h = OSDSuppressorHarness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.suppressor.setEngaged(false)
        h.suppressor.setEngaged(true)

        await settle()
        #expect(h.volume.applied.isEmpty)
        #expect(h.suppressor.isEngaged)
    }

    @Test func aSuspensionMidHoldReleasesTheKeyInsteadOfMutingTheRestOfIt() async {
        // The AirPods-drop-while-holding-volume-down case. The swallow latch is
        // what keeps a held key on the phase it committed to, so before this it
        // outlived the suspension: every autorepeat down stayed swallowed, every
        // apply was dropped by the suspension guard, and the user got neither our
        // bar nor the native OSD until they let go.
        //
        // The suite could not see it: `press()` sends a matched down+up, and the
        // loose `pressDown` calls elsewhere are always one isolated down per key —
        // two consecutive downs on one key never happened, which is precisely what
        // a hold is.
        let h = OSDSuppressorHarness()
        h.volume.writeIsDead = true   // the write is accepted and nothing moves
        h.suppressor.setEngaged(true)

        #expect(h.keys.pressDown(.volumeDown) == true)   // first down: swallowed
        #expect(await eventually { h.suppressor.suspendedDomains.contains(.volume) })

        // Still held. The autorepeats must reach the system now.
        #expect(h.keys.pressDown(.volumeDown) == false)
        #expect(h.keys.pressDown(.volumeDown) == false)

        // And the up goes with them: the system saw those downs, so withholding
        // the up would leave it repeating a key nobody released.
        #expect(h.keys.pressUp(.volumeDown) == false)
    }
}
