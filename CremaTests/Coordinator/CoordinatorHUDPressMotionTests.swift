import Testing
@testable import Crema

/// The bar's answer to a press: pulled past its end while a key pushes against
/// it, grown while the HUD is in use, each settling on its own hold
/// (docs/DECISIONS.md: the-bar-answers-the-press). Their timers run on the
/// harness's `motionClock`, apart from the presentation timeline.
@MainActor
struct CoordinatorHUDPressMotionTests {

    @Test func aPressPastTheEndPullsThatEndUntilItsKeyComesUp() async {
        let h = CoordinatorHarness()

        h.coordinator.hudPushedPastEnd(.volumeUp)
        #expect(h.coordinator.hudPush == HUDPush(kind: .volume, end: .end))

        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushMinimumHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDPushMinimumHold)
        await settle()
        #expect(h.coordinator.hudPush == HUDPush(kind: .volume, end: .end))

        // Letting go at once is also the barrier for the line above: had the
        // floor not run out yet, the up would only be owed.
        h.coordinator.hudPushReleased(.volumeUp)
        #expect(h.coordinator.hudPush == nil)
    }

    @Test func aTapKeepsThePullForItsFloor() async {
        // A tap's up reaches the Coordinator right after its push.
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.screenBrightnessDown)
        h.coordinator.hudPushReleased(.screenBrightnessDown)
        #expect(h.coordinator.hudPush == HUDPush(kind: .screenBrightness, end: .start))

        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushMinimumHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDPushMinimumHold)
        #expect(await eventually { h.coordinator.hudPush == nil })
    }

    @Test func aPullWhoseUpNeverArrivesLetsGoAfterTheLongestHold() async {
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.volumeUp)

        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushLongestHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDPushLongestHold)
        #expect(await eventually { h.coordinator.hudPush == nil })
    }

    @Test func theUpOfAnotherKeyLeavesThePull() async {
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.volumeUp)
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushMinimumHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDPushMinimumHold)
        await settle()

        h.coordinator.hudPushReleased(.volumeDown)
        h.coordinator.hudPushReleased(.mute)
        #expect(h.coordinator.hudPush == HUDPush(kind: .volume, end: .end))

        h.coordinator.hudPushReleased(.volumeUp)
        #expect(h.coordinator.hudPush == nil)
    }

    @Test func aPushEngagesNothingOfItsOwn() {
        // The reading behind the press grows the bar; growing it here would put
        // the growth and the pull in one transaction, under one spring.
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.volumeUp)
        #expect(!h.coordinator.hudIsEngaged)
    }

    @Test func eachKeyNamesItsOwnKindAndEndAndMuteNamesNone() {
        #expect(HUDPush(key: .volumeDown) == HUDPush(kind: .volume, end: .start))
        #expect(HUDPush(key: .screenBrightnessUp) == HUDPush(kind: .screenBrightness, end: .end))
        #expect(HUDPush(key: .screenBrightnessDown) == HUDPush(kind: .screenBrightness, end: .start))
        #expect(HUDPush(key: .keyboardBrightnessUp) == HUDPush(kind: .keyboardBrightness, end: .end))
        #expect(HUDPush(key: .keyboardBrightnessDown) == HUDPush(kind: .keyboardBrightness, end: .start))
        #expect(HUDPush(key: .mute) == nil)
    }

    @Test func aHeldKeyKeepsTheBarPulledOut() async {
        // Autorepeat at the end: each press re-arms the longest hold, so a key
        // held past it is never let go under the hand.
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.volumeUp)
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushLongestHold)

        h.coordinator.hudPushedPastEnd(.volumeUp)

        #expect(await eventually { h.motionClock.cancelledCount >= 1 })
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDPushLongestHold)
        #expect(h.coordinator.hudPush == HUDPush(kind: .volume, end: .end))
    }

    @Test func aHUDGrowsTheBarAndItSettlesThinAfterItsHold() async {
        let h = CoordinatorHarness()
        #expect(!h.coordinator.hudIsEngaged)

        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.hudIsEngaged })

        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDEngagedHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDEngagedHold)
        #expect(await eventually { !h.coordinator.hudIsEngaged })
        // Settling thin is not leaving: the HUD is still up.
        #expect(h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)))
    }

    @Test func aDragHoldsTheBarGrownUntilTheRelease() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDEngagedHold)

        h.coordinator.hudSliderChanged(to: 0.6)
        // The settle armed by the HUD is cancelled and none takes its place while
        // the hand holds the bar; this read is synchronous after the call.
        #expect(!h.motionClock.isParked(delay: Coordinator.defaultHUDEngagedHold))
        #expect(h.coordinator.hudIsEngaged)

        h.coordinator.hudSliderReleased()
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDEngagedHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDEngagedHold)
        #expect(await eventually { !h.coordinator.hudIsEngaged })
    }

    @Test func bothSettleWhileTheHUDIsStillUp() {
        // The settle is part of what the HUD shows: a hold that outlived the
        // revert would fade every HUD out grown and never show the thin bar.
        #expect(Coordinator.defaultHUDPushMinimumHold < Coordinator.defaultHUDEngagedHold)
        #expect(Coordinator.defaultHUDEngagedHold < Coordinator.defaultHUDRevertDelay)
    }
}
