import Testing
@testable import Crema

/// What the suppressor DOES with the pointer rule's answer: which brightness key
/// it takes, which one it hands back whole, what it tells the local bar when it
/// hands one back, and how a press that began under one answer ends under it
/// (docs/DECISIONS.md: brightness-key-follows-the-pointer). The rule itself is
/// pinned in BrightnessKeyTargetingTests; here the answer is injected, so nothing
/// reads a cursor.
///
/// The claim under all of it: this app reads and writes the built-in panel and no
/// other, so a key aimed anywhere else is not its to swallow. Swallowing it would
/// either move a screen the user is not looking at — the reported bug — or eat a
/// press and draw nothing, and a consumed key always owes feedback.
@MainActor
struct BrightnessKeyPointerGateTests {
    @Test func aKeyAimedAtTheBuiltInPanelIsTakenAndApplied() async {
        let harness = OSDSuppressorHarness()
        harness.suppressor.setEngaged(true)

        let press = harness.keys.press(.screenBrightnessUp)

        #expect(press.down)
        #expect(press.up)
        #expect(await eventually { harness.screen.applied == [0.5 + OSDTest.step] })
    }

    @Test func aKeyAimedAtAnotherDisplayIsHandedBackWhole() async {
        let harness = OSDSuppressorHarness()
        harness.brightnessTarget.value = .anotherDisplay
        harness.suppressor.setEngaged(true)

        let press = harness.keys.press(.screenBrightnessUp)
        await settle()

        // Both phases pass: a swallowed down with a leaked up orphans the pair.
        #expect(!press.down)
        #expect(!press.up)
        #expect(harness.screen.applied.isEmpty)
        // And nothing is broken by it: a key that was never ours is not a failed
        // apply, so the domain must not suspend, escalate, or reach the menu.
        #expect(!harness.suppressor.suspendedDomains.contains(.screenBrightness))
        #expect(harness.suppressor.longSuspendedDomains.isEmpty)
        #expect(harness.suspensionChanges == 0)
    }

    @Test func aPointerNobodyCanPlaceIsNotAnInvitationToGuess() async {
        let harness = OSDSuppressorHarness()
        harness.brightnessTarget.value = .unknown
        harness.suppressor.setEngaged(true)

        let press = harness.keys.press(.screenBrightnessDown)
        await settle()

        #expect(!press.down)
        #expect(!press.up)
        #expect(harness.screen.applied.isEmpty)
    }

    @Test func aHandedBackKeyTellsTheLocalBarToStandDown() async {
        // The press the app declines is drawn by the system, so the local
        // brightness source must spend its key window instead of putting a second
        // bar over that indicator — the same seam the neighbour's report uses
        // (docs/DECISIONS.md: betterdisplay-osd-source).
        let harness = OSDSuppressorHarness()
        let declined = CounterBox()
        harness.suppressor.onHandedBackToTheSystem = { [declined] _ in declined.count += 1 }
        harness.suppressor.setEngaged(true)

        // Ours: applied, drawn by us, nothing to stand down.
        harness.keys.press(.screenBrightnessUp)
        #expect(await eventually { harness.screen.applied == [0.5 + OSDTest.step] })
        // Box.count is a running counter, not a collection.
        // swiftlint:disable:next empty_count
        #expect(declined.count == 0)

        harness.brightnessTarget.value = .anotherDisplay
        harness.keys.press(.screenBrightnessUp)

        #expect(await eventually { declined.count == 1 })
        #expect(harness.screen.applied == [0.5 + OSDTest.step])
    }

    @Test func onlyTheDomainADisplayCanOwnAnswersToThePointer() async {
        let harness = OSDSuppressorHarness()
        harness.brightnessTarget.value = .anotherDisplay
        harness.suppressor.setEngaged(true)

        // Volume belongs to no display and the backlight to the one keyboard, so
        // where the pointer rests says nothing about either.
        for key in [MediaKey.volumeUp, .mute, .keyboardBrightnessUp] {
            #expect(harness.keys.pressDown(key))
            #expect(harness.keys.pressUp(key))
        }
        #expect(await eventually { harness.keyboard.applied == [0.5 + OSDTest.step] })
    }

    @Test func aPressKeepsTheVerdictItsFirstDownCommittedTo() async {
        let harness = OSDSuppressorHarness()
        harness.brightnessTarget.value = .anotherDisplay
        harness.suppressor.setEngaged(true)

        #expect(!harness.keys.pressDown(.screenBrightnessUp))
        // The pointer crosses onto the laptop mid-hold. The verdict must not flip:
        // swallowing the rest of a press the system already saw the down of leaves
        // it downs with no up — half a press nobody closes.
        harness.brightnessTarget.value = .builtIn
        #expect(!harness.keys.pressDown(.screenBrightnessUp))   // autorepeat
        #expect(!harness.keys.pressUp(.screenBrightnessUp))
        await settle()
        #expect(harness.screen.applied.isEmpty)

        // The NEXT press is judged afresh — and now it is ours.
        #expect(harness.keys.pressDown(.screenBrightnessUp))
        #expect(harness.keys.pressUp(.screenBrightnessUp))
        #expect(await eventually { harness.screen.applied == [0.5 + OSDTest.step] })
    }

    @Test func aPressThatStartedAsOursStaysOursIfThePointerLeaves() {
        let harness = OSDSuppressorHarness()
        harness.suppressor.setEngaged(true)

        #expect(harness.keys.pressDown(.screenBrightnessUp))
        harness.brightnessTarget.value = .anotherDisplay
        #expect(harness.keys.pressDown(.screenBrightnessUp))   // autorepeat, still ours
        #expect(harness.keys.pressUp(.screenBrightnessUp))     // and the up, or the pair orphans
    }
}
