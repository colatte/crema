import Testing
@testable import Crema

/// The bar's answer to a key: held from its down to its up, counting the presses
/// that found the level at the end, never shorter than a tap needs to be seen
/// nor longer than a lost up allows; and the drag's growth, settling on its own
/// hold (docs/DECISIONS.md: the-bar-answers-the-press). Their timers run on the
/// harness's `motionClock`, apart from the presentation timeline.
@MainActor
struct CoordinatorHUDPressMotionTests {

    private let floor = Coordinator.defaultHUDPressMinimumHold
    private let ceiling = Coordinator.defaultHUDPressLongestHold

    @Test func aKeyIsAnsweredFromItsDownToItsUp() async {
        let h = CoordinatorHarness()

        h.coordinator.hudKeyPressed(.volumeUp)
        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .end))

        await h.motionClock.waitForSleep(delay: floor)
        h.motionClock.advance(delay: floor)
        await settle()
        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .end))

        // Letting go at once is also the barrier for the line above: had the
        // floor not run out yet, the up would only be owed.
        h.coordinator.hudKeyReleased(.volumeUp)
        #expect(h.coordinator.hudPress == nil)
    }

    @Test func aTapIsAnsweredForTheFloor() async {
        // A tap's up reaches the Coordinator right after its down.
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.screenBrightnessDown)
        h.coordinator.hudKeyReleased(.screenBrightnessDown)
        #expect(h.coordinator.hudPress == HUDPress(kind: .screenBrightness, end: .start))

        await h.motionClock.waitForSleep(delay: floor)
        h.motionClock.advance(delay: floor)
        #expect(await eventually { h.coordinator.hudPress == nil })
    }

    @Test func eachPressPastTheEndOfOneHoldCountsOnce() {
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)
        h.coordinator.hudPushedPastEnd(.volumeUp)
        // An autorepeat down keeps the count; its verdict adds to it.
        h.coordinator.hudKeyPressed(.volumeUp)
        h.coordinator.hudPushedPastEnd(.volumeUp)

        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .end, stepsPastEnd: 2))
    }

    @Test func aPushWhoseDownWasNotSeenStartsAPressOfItsOwn() {
        let h = CoordinatorHarness()
        h.coordinator.hudPushedPastEnd(.keyboardBrightnessUp)
        #expect(h.coordinator.hudPress == HUDPress(kind: .keyboardBrightness, end: .end, stepsPastEnd: 1))
    }

    @Test func anotherKeyStartsAFreshPress() {
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)
        h.coordinator.hudPushedPastEnd(.volumeUp)

        h.coordinator.hudKeyPressed(.volumeDown)

        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .start))
    }

    @Test func aPressWhoseUpNeverArrivesLetsGoAfterTheLongestHold() async {
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)

        await h.motionClock.waitForSleep(delay: ceiling)
        h.motionClock.advance(delay: ceiling)
        #expect(await eventually { h.coordinator.hudPress == nil })
    }

    @Test func theUpOfAnotherKeyLeavesThePress() async {
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)
        await h.motionClock.waitForSleep(delay: floor)
        h.motionClock.advance(delay: floor)
        await settle()

        h.coordinator.hudKeyReleased(.volumeDown)
        h.coordinator.hudKeyReleased(.mute)
        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .end))

        h.coordinator.hudKeyReleased(.volumeUp)
        #expect(h.coordinator.hudPress == nil)
    }

    @Test func aHeldKeyIsNeverLetGoUnderTheHand() async {
        // Each autorepeat re-arms the longest hold.
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)
        await h.motionClock.waitForSleep(delay: ceiling)

        h.coordinator.hudKeyPressed(.volumeUp)

        #expect(await eventually { h.motionClock.cancelledCount >= 1 })
        await h.motionClock.waitForSleep(delay: ceiling)
        #expect(h.coordinator.hudPress == HUDPress(kind: .volume, end: .end))
    }

    @Test func eachKeyNamesItsOwnKindAndEndAndMuteNamesNone() {
        #expect(HUDPress(key: .volumeUp) == HUDPress(kind: .volume, end: .end))
        #expect(HUDPress(key: .volumeDown) == HUDPress(kind: .volume, end: .start))
        #expect(HUDPress(key: .screenBrightnessUp) == HUDPress(kind: .screenBrightness, end: .end))
        #expect(HUDPress(key: .screenBrightnessDown) == HUDPress(kind: .screenBrightness, end: .start))
        #expect(HUDPress(key: .keyboardBrightnessUp) == HUDPress(kind: .keyboardBrightness, end: .end))
        #expect(HUDPress(key: .keyboardBrightnessDown) == HUDPress(kind: .keyboardBrightness, end: .start))
        #expect(HUDPress(key: .mute) == nil)
    }

    @Test func neitherAKeyNorItsReadingGrowsTheBar() async {
        // The press answers with its own shape, and growing the bar here too would
        // put the growth and the press in one transaction, under one spring.
        let h = CoordinatorHarness()
        h.coordinator.hudKeyPressed(.volumeUp)
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        #expect(!h.coordinator.hudIsEngaged)
    }

    @Test func aDragHoldsTheBarGrownUntilTheReleaseThenSettlesThin() async {
        let h = CoordinatorHarness()
        h.hudSource.emit(SystemHUD(kind: .volume, value: 0.5))
        #expect(await eventually { h.coordinator.state == .hud(SystemHUD(kind: .volume, value: 0.5)) })

        h.coordinator.hudSliderChanged(to: 0.6)
        // No settle while the hand holds the bar; this read is synchronous after
        // the call.
        #expect(!h.motionClock.isParked(delay: Coordinator.defaultHUDEngagedHold))
        #expect(h.coordinator.hudIsEngaged)

        h.coordinator.hudSliderReleased()
        await h.motionClock.waitForSleep(delay: Coordinator.defaultHUDEngagedHold)
        h.motionClock.advance(delay: Coordinator.defaultHUDEngagedHold)
        #expect(await eventually { !h.coordinator.hudIsEngaged })
        // Settling thin is not leaving: the HUD is still up.
        guard case .hud = h.coordinator.state else {
            Issue.record("the HUD left with the settle")
            return
        }
    }

    @Test func bothSettleWhileTheHUDIsStillUp() {
        // The settle is part of what the HUD shows: a hold that outlived the
        // revert would fade every HUD out grown and never show the thin bar.
        #expect(Coordinator.defaultHUDPressMinimumHold < Coordinator.defaultHUDRevertDelay)
        #expect(Coordinator.defaultHUDEngagedHold < Coordinator.defaultHUDRevertDelay)
    }
}
