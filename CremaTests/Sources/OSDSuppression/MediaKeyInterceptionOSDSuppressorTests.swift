import Testing
@testable import Crema

/// The production suppressor over mocked channels and a captured
/// consumer: stepping, ordering, mute, capability no-ops, and every failure
/// path (throwing, dead write, unreadable, hung) ending in a self-disengage —
/// with the native behavior restored, the user is never left without volume
/// control.
@MainActor
struct MediaKeyInterceptionOSDSuppressorTests {

    @MainActor
    private struct Harness {
        let keys = MockMediaKeyConsuming()
        let volume = MockOSDVolumeChannel()
        let screen = MockOSDChannel()
        let keyboard = MockOSDChannel()
        let clock = TestSleepClock()
        let suppressor: MediaKeyInterceptionOSDSuppressor
        let disengages = Box()

        @MainActor final class Box { var count = 0 }

        init() {
            suppressor = MediaKeyInterceptionOSDSuppressor(
                keys: keys,
                volume: volume,
                screen: screen,
                keyboard: keyboard,
                clock: clock
            )
            suppressor.onAutoDisengage = { [disengages] in disengages.count += 1 }
        }
    }

    @Test func engagingInstallsTheConsumerAndDisengagingRemovesIt() {
        let h = Harness()
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
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        #expect(await eventually { h.volume.applied == [0.5 + 1.0 / 16.0] })

        h.keys.press(.volumeDown)
        #expect(await eventually { h.volume.applied.count == 2 && h.volume.value == 0.5 })
        #expect(h.suppressor.isEngaged)   // verified applies keep it on
    }

    @Test func optionShiftStepsByAQuarterStep() async {
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp, fine: true)

        #expect(await eventually { h.volume.applied == [0.5 + 1.0 / 64.0] })
    }

    @Test func anAutorepeatBurstNeverLosesSteps() async {
        // Three key-downs land before the first async apply finishes: applies
        // must chain, each reading the previous one's result — interleaved
        // read-modify-write would apply the same base twice.
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)

        let step = 1.0 / 16.0
        #expect(await eventually { h.volume.applied == [0.5 + step, 0.5 + 2 * step, 0.5 + 3 * step] })
    }

    @Test func mixedCoarseAndFineStepsBindPerKey() async {
        // The fine flag must ride each key through the chain — a sticky flag
        // would survive into the next press.
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp, fine: true)

        let coarse = 1.0 / 16.0
        let fine = 1.0 / 64.0
        #expect(await eventually { h.volume.applied == [0.5 + coarse, 0.5 + coarse + fine] })
    }

    @Test func mutePressedInsideAVolumeBurstAppliesInOrder() async {
        // Cross-kind ordering: the mute toggles against the state the burst
        // left, and the following volume-up unmutes against the fresh state.
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.mute)
        h.keys.press(.volumeUp)

        let step = 1.0 / 16.0
        #expect(await eventually { h.volume.applied == [0.5 + step, 0.5 + 2 * step] })
        #expect(h.volume.mutedWrites == [true, false])   // mute on, then volume-up unmuted
        #expect(h.volume.muted == false)
    }

    @Test func muteTogglesBothWaysAndVerifies() async {
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.mute)
        #expect(await eventually { h.volume.muted == true })

        h.keys.press(.mute)
        #expect(await eventually { h.volume.muted == false })
        #expect(h.volume.mutedWrites == [true, false])
        #expect(h.suppressor.isEngaged)
    }

    @Test func volumeUpUnmutesFirstLikeTheNativeHandler() async {
        let h = Harness()
        h.volume.muted = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.volume.muted == false && h.volume.applied.count == 1 })
    }

    @Test func aDeadMutePlaneOnVolumeUpDisengages() async {
        // The unmute is a verified write like any other: consumed volume-up
        // with a silently dead mute plane would read as "key does nothing".
        let h = Harness()
        h.volume.muted = true
        h.volume.muteWriteIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.disengages.count == 1)
    }

    @Test func aBoundaryStepIsANoOpNotAFailure() async {
        let h = Harness()
        h.volume.value = 1.0
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { h.volume.applied == [1.0] })
        #expect(h.suppressor.isEngaged)
        #expect(h.disengages.count == 0)
    }

    @Test func anAbsentCapabilityIsANoOpNeverAFailure() async {
        // HDMI/USB outputs without volume or mute, Macs without a keyboard
        // backlight: the native handler no-ops there (prohibited HUD), and
        // disengaging would self-destruct the feature on ordinary hardware —
        // and worse, flip the persisted opt-in behind the user's back.
        let h = Harness()
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
        #expect(h.disengages.count == 0)
    }

    @Test func brightnessKeysRouteToTheirChannels() async {
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        h.keys.press(.keyboardBrightnessDown)

        #expect(await eventually { h.screen.applied == [0.5 + 1.0 / 16.0] })
        #expect(await eventually { h.keyboard.applied == [0.5 - 1.0 / 16.0] })
        #expect(h.volume.applied.isEmpty)
    }

    @Test func verifiedAppliesReportThroughOnApplied() async {
        // The post-apply hook is what refreshes the brightness HUD with the
        // applied value (the router's key-time sample reads the old one).
        let h = Harness()
        let seen = Harness.Box()
        h.suppressor.onApplied = { [seen] _ in seen.count += 1 }
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        h.keys.press(.volumeUp)

        #expect(await eventually { seen.count == 2 })
    }

    @Test func aThrowingApplyDisengagesAndReports() async {
        let h = Harness()
        h.screen.applyThrows = true
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)

        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(!h.keys.isConsuming)   // native behavior restored
        #expect(h.disengages.count == 1)
    }

    @Test func aDeadWriteFailsTheSelfCheckAndDisengages() async {
        // The dangerous failure: the actuator accepts the write but nothing
        // moves — without the read-back check the user would be stranded on a
        // consumed, dead key.
        let h = Harness()
        h.volume.writeIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)

        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.disengages.count == 1)
    }

    @Test func aHungApplyHitsTheDeadlineAndDisengages() async {
        // The failure the read-back can't see: an apply that never completes
        // (coreaudiod stall). Keys keep being consumed while nothing works —
        // the deadline converts the hang into a failure and the native
        // behavior comes back.
        let h = Harness()
        h.screen.applyHangs = true
        h.suppressor.setEngaged(true)

        h.keys.press(.screenBrightnessUp)
        await h.clock.waitForSleep(delay: MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline)
        h.clock.advance(delay: MediaKeyInterceptionOSDSuppressor.defaultApplyDeadline)

        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(!h.keys.isConsuming)
        #expect(h.disengages.count == 1)
        #expect(h.screen.applied.isEmpty)   // the hung apply never landed
    }

    @Test func aBurstOfFailuresReportsExactlyOnceAndDropsTheQueue() async {
        let h = Harness()
        h.volume.writeIsDead = true
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)
        h.keys.press(.volumeUp)

        #expect(await eventually { !h.suppressor.isEngaged })
        await settle()
        // One failure disengages; the queued keys fall through the generation
        // guard — three failure reports would flip the toggle thrice.
        #expect(h.disengages.count == 1)
        #expect(h.volume.applied.count == 1)
    }

    @Test func anUnreadableCurrentValueDisengages() async {
        let h = Harness()
        h.keyboard.value = nil
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { !h.suppressor.isEngaged })
        #expect(h.disengages.count == 1)
    }

    @Test func keysConsumedBeforeADisengageLandsDoNotApply() async {
        let h = Harness()
        h.suppressor.setEngaged(true)

        // The tap's consumer hops to the main actor: a disengage that runs
        // before the hop lands must drop the queued key.
        h.keys.press(.volumeUp)
        h.suppressor.setEngaged(false)

        await settle()
        #expect(h.volume.applied.isEmpty)
    }

    @Test func aStaleKeyFromABygoneEngagementNeverAppliesAfterAReengage() async {
        // The generation guard: a bare isEngaged bool would let a key
        // consumed just before a disengage apply into the new engagement.
        let h = Harness()
        h.suppressor.setEngaged(true)

        h.keys.press(.volumeUp)
        h.suppressor.setEngaged(false)
        h.suppressor.setEngaged(true)

        await settle()
        #expect(h.volume.applied.isEmpty)
        #expect(h.suppressor.isEngaged)
    }

    @Test func reengagingAfterAnAutoDisengageWorks() async {
        // The degradation is not a latch: fixing the cause (here, the write
        // path coming back) and re-opting-in restores the feature.
        let h = Harness()
        h.volume.writeIsDead = true
        h.suppressor.setEngaged(true)
        h.keys.press(.volumeUp)
        #expect(await eventually { !h.suppressor.isEngaged })

        h.volume.writeIsDead = false
        h.suppressor.setEngaged(true)
        h.keys.press(.volumeUp)

        // The second apply re-reads the unmoved base — the post-recovery
        // contract is a fresh, verified step from wherever the value stands.
        #expect(await eventually { h.volume.applied == [0.5625, 0.5625] && h.volume.value == 0.5625 })
        #expect(h.suppressor.isEngaged)
    }
}
