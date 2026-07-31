import Testing
@testable import Crema

/// A consumed key always owes feedback. A channel that reports no such control is
/// not a failure — nothing is broken and there is nothing for a probe to recover —
/// but swallowing its key drew nothing AND let nothing through, so the press simply
/// vanished: no bar of ours, no native OSD, one log line as the only trace. The fix
/// is the shape the pointer rule already uses: hand the key back whole and let the
/// system apply it and draw its own indicator (docs/DECISIONS.md:
/// absent-capability-hands-the-key-back).
///
/// The absence is learned on the apply — the only place that asks the channel — and
/// read at the press, so the first press of an episode is the one that buys the
/// answer. Every test here pins that shape, and every one of them also pins what
/// must NOT change: an absent capability never suspends a domain, never escalates,
/// and never reaches the menu.
@MainActor
struct AbsentCapabilityHandbackTests {

    @Test func theFirstPressBuysTheAnswerAndEveryPressAfterItIsHandedBack() async {
        let h = OSDSuppressorHarness()
        h.screen.available = false   // the private symbols never resolved
        h.suppressor.setEngaged(true)

        // Nothing knows yet, so this press is taken and writes nothing. It is the
        // declared price of learning on the apply.
        let bought = h.keys.press(.screenBrightnessUp)
        #expect(bought.down)
        #expect(bought.up)
        #expect(await eventually {
            let down = h.keys.pressDown(.screenBrightnessUp)
            h.keys.pressUp(.screenBrightnessUp)
            return !down
        }, "the absence never landed for .screenBrightnessUp")

        // From here the key goes to the system, which applies it and draws its own
        // indicator. Both phases, or the system is left half a press.
        let handedBack = h.keys.press(.screenBrightnessUp)
        #expect(!handedBack.down)
        #expect(!handedBack.up)

        // The settle IS needed here and only here: the two lines above read a value
        // the press already returned, while this one asserts that nothing arrives
        // afterwards — which is the negative wait settle() is documented for.
        await settle()
        #expect(h.screen.applied.isEmpty)
        #expect(h.suppressor.isEngaged)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
        #expect(h.suspensionChanges == 0)
    }

    @Test func onlyTheMissingControlIsHandedBackNotItsWholeDomain() async {
        // Mute and the volume level are separate Core Audio properties on the same
        // device and plenty of outputs expose one without the other — while both keys
        // share ONE suspension domain. Marking the domain would hand the volume keys
        // of a perfectly controllable device to the system, losing the app's bar for
        // the domain that is the core of the feature.
        let h = OSDSuppressorHarness()
        h.volume.muteSupported = false
        h.suppressor.setEngaged(true)

        h.keys.press(.mute)   // buys the answer
        #expect(await eventually {
            let down = h.keys.pressDown(.mute)
            h.keys.pressUp(.mute)
            return !down
        }, "the absence never landed for .mute")

        let mute = h.keys.press(.mute)
        let level = h.keys.press(.volumeUp)

        #expect(!mute.down)
        #expect(!mute.up)
        #expect(level.down)
        #expect(level.up)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })
        #expect(h.volume.mutedWrites.isEmpty)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
    }

    @Test func aHeldKeyStopsBeingSwallowedTheMomentTheAbsenceIsLearned() async {
        // The decider commits a verdict at the first down and keeps it for the whole
        // press, so without a latch release paired to the mark, a key HELD while the
        // apply discovers the absence stays swallowed until the user lets go: press,
        // nothing, for the length of the hold. That is the exact dead gesture
        // `suspend` releases the latch to avoid, and holding volume-down to zero on
        // an output with no volume control is how a person meets it.
        let h = OSDSuppressorHarness()
        h.volume.available = false
        h.suppressor.setEngaged(true)

        #expect(h.keys.pressDown(.volumeDown))   // the first down buys the answer
        // Autorepeats arrive at the HID timer's cadence, not the user's; the first
        // one after the apply answers must reach the system.
        #expect(await eventually { !h.keys.pressDown(.volumeDown) })

        // And the up must go the SAME way the downs now go. This is the half the
        // migration exists for and the half a partial fix silently loses: leaving the
        // key latched while also marking it passed lets the downs through and keeps
        // swallowing the up, so the system collects downs that never close. Measured
        // — that mutation survives every other assertion in this file.
        #expect(!h.keys.pressUp(.volumeDown))

        #expect(h.volume.applied.isEmpty)
        #expect(h.suppressor.suspendedDomains.isEmpty)
        #expect(h.suppressor.longSuspendedDomains.isEmpty)
    }

    @Test func theNextPressAsksAgainWhenTheControlComesBack() async {
        // Invalidation is by evidence, never by timer: the backlight can be missing
        // at a cold boot and answer moments later, so the user's next press on a
        // handed-back key is what re-asks. It costs one native HUD on the way back —
        // the same price the pointer rule already pays.
        let h = OSDSuppressorHarness()
        h.keyboard.available = false
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)   // buys the answer
        #expect(await eventually {
            let down = h.keys.pressDown(.keyboardBrightnessUp)
            h.keys.pressUp(.keyboardBrightnessUp)
            return !down
        }, "the absence never landed for .keyboardBrightnessUp")
        #expect(!h.keys.pressDown(.keyboardBrightnessUp))
        h.keys.pressUp(.keyboardBrightnessUp)

        // The service comes up. The press that re-asks is still handed back; the one
        // after it is ours again. Each probe press is completed with its up, or the
        // pass latch would hold the verdict past the recovery.
        h.keyboard.available = true
        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually {
            let down = h.keys.pressDown(.keyboardBrightnessUp)
            h.keys.pressUp(.keyboardBrightnessUp)
            return down
        })
        #expect(await eventually { h.keyboard.applied == [0.5 + OSDTest.step] })
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }

    @Test func anEngagementFlipForgetsEveryAbsence() async {
        // Every other axis is born healthy on a flip — suspensions, probes, the
        // write-health counters — and this one must be too: a disengage is a lock or
        // a toggle, and what the route could do before it says nothing about now.
        let h = OSDSuppressorHarness()
        h.keyboard.available = false
        h.suppressor.setEngaged(true)

        h.keys.press(.keyboardBrightnessUp)
        #expect(await eventually {
            let down = h.keys.pressDown(.keyboardBrightnessUp)
            h.keys.pressUp(.keyboardBrightnessUp)
            return !down
        }, "the absence never landed for .keyboardBrightnessUp")
        #expect(!h.keys.pressDown(.keyboardBrightnessUp))
        h.keys.pressUp(.keyboardBrightnessUp)

        h.suppressor.setEngaged(false)
        h.suppressor.setEngaged(true)

        // Taken again, and it no-ops again: the absence is re-learned, not remembered.
        let press = h.keys.press(.keyboardBrightnessUp)
        await settle()
        #expect(press.down)
        #expect(press.up)
        #expect(h.keyboard.applied.isEmpty)
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }

    @Test func aKeyHandedBackForAMissingControlStandsTheLocalBarDownToo() async {
        // The tap keeps OBSERVING a key it hands back, so the router arms the
        // brightness poll and the poll would read the value macOS just moved — a
        // second bar over the native indicator, on the very press that recovers the
        // channel. One press, one indicator, whoever drew it; the reason for the
        // handback does not change that.
        let h = OSDSuppressorHarness()
        let handedBack = CounterBox()
        h.suppressor.onHandedBackToTheSystem = { [handedBack] _ in handedBack.count += 1 }
        h.keyboard.available = false
        h.suppressor.setEngaged(true)

        // The press that buys the answer is ours: we draw nothing, but nobody else
        // does either, so there is no window to spend. Negative wait, which is what
        // settle() is for.
        h.keys.press(.keyboardBrightnessUp)
        await settle()
        // swiftlint:disable:next empty_count
        #expect(handedBack.count == 0)

        #expect(await eventually {
            let down = h.keys.pressDown(.keyboardBrightnessUp)
            h.keys.pressUp(.keyboardBrightnessUp)
            return !down
        }, "the absence never landed for .keyboardBrightnessUp")

        // Measured as an INCREASE, never as an absolute: the probe above presses the
        // key until the absence lands, and every one of those presses is itself
        // handed back. An `== 1` here would be asserting that the probe ran exactly
        // once, which is a fact about the scheduler and not about the seam.
        let before = handedBack.count
        h.keys.press(.keyboardBrightnessUp)

        #expect(await eventually { handedBack.count > before })
    }

    @Test func theMuteAbsenceIsNamedByTheGuardThatAnsweredNotByTheKeyThatRanIt() async {
        // A volume-up press consults TWO capabilities: the level, and — for its
        // unmute-first step — the mute plane. This output has the first and not the
        // second, which the channel protocol calls ordinary hardware. What is learned
        // is therefore named by the GUARD that answered: name it after the KEY and
        // `.volumeLevel` goes absent on a device whose level is perfect, handing
        // volume-up and volume-down to the system and losing the app's own bar for
        // the domain that is the point of the feature.
        //
        // It is also the ONLY test that reaches the unmute-first guard's own learning
        // site. `applyMute` asks the same question, so a suite that always learns
        // through the mute KEY stays green with that site deleted — and it is the
        // more frequent of the two by a wide margin, since volume-up is pressed far
        // more than mute. Deleting it leaves the mute key swallowed forever for a
        // user who only ever touches volume.
        let h = OSDSuppressorHarness()
        h.volume.muteSupported = false   // volume works; this output has no mute plane
        h.suppressor.setEngaged(true)

        // Only volume-up is ever pressed here, and it stays ours: taken, applied, and
        // the mute guard it runs on the way is what answers. The landed write is the
        // deterministic proof that the guard already ran.
        let level = h.keys.press(.volumeUp)
        #expect(level.down)
        #expect(level.up)
        #expect(await eventually { h.volume.applied == [0.5 + OSDTest.step] })

        // Mute is pressed EXACTLY ONCE, and that is the whole discriminator. A probe
        // loop would press it repeatedly — and `applyMute` asks the same question, so
        // the second press would learn through the mute key's own guard and the test
        // would pass with this site deleted. Measured: it did. The claim is that a
        // user who only ever touched VOLUME already knows, so the FIRST mute press is
        // handed back.
        //
        // No wait is needed and none is used: the landed write above happens AFTER
        // the unmute-first guard inside the same apply, so it is proof the guard has
        // already answered.
        let mute = h.keys.press(.mute)
        #expect(!mute.down, "volume-up never taught the app that this route has no mute plane")
        #expect(!mute.up)

        // And the volume keys are untouched: the domain they share is not what was
        // marked.
        let again = h.keys.press(.volumeUp)
        #expect(again.down)
        #expect(again.up)
        #expect(h.volume.mutedWrites.isEmpty)
        #expect(h.suppressor.suspendedDomains.isEmpty)
    }
}
