import Testing
@testable import Crema

/// A bar drawn from a neighbouring app's report, and what a drag on it owes the
/// user. The three pins here are the three ways this went wrong in review:
/// a frozen bar, a dead control, and a write on the wrong scale
/// (docs/DECISIONS.md: betterdisplay-osd-source).
@MainActor
struct CoordinatorNeighbourBrightnessTests {

    private func neighbourHUD(_ value: Double = 0.5) -> SystemHUD {
        SystemHUD(kind: .screenBrightness, value: value, authority: .betterDisplay)
    }

    @Test func aDragOnTheNeighboursBarGoesBackToTheNeighbour() async {
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)

        #expect(await eventually { h.external?.commands.isEmpty == false })
        #expect(h.external?.commands == [.setBrightness(0.8, display: nil)])
        #expect(h.screen.commands.isEmpty)   // never on the system's own scale
    }

    @Test func aDragOnTheSystemsOwnBarStillGoesToTheSystem() async {
        // The neighbour being wired must not capture bars it did not draw.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.3)

        #expect(await eventually { h.screen.commands.isEmpty == false })
        #expect(h.external?.commands.isEmpty == true)
    }

    @Test func theBarFollowsTheFingerWithoutWaitingForTheRoundTrip() async {
        // The slider has no local value: it draws whatever the last HUD said. A
        // round-trip to another process is not instant and may never answer, so
        // the level is on screen before the write leaves.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.hudSource.emit(neighbourHUD(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)

        #expect(h.coordinator.state == .hud(neighbourHUD(0.9)))   // already, synchronously
    }

    @Test func aWriteThatFailedIsNeverEchoedAsApplied() async {
        // The echo exists to close the HUD loop, and it must close it on the
        // truth: reporting a failed write as applied pokes the sampler, which
        // re-reads and draws a level the display never went to — a bar that lies
        // about a control that did nothing.
        let h = CoordinatorHarness()
        let applied = Applied()
        h.coordinator.onBrightnessApplied = { applied.record($0) }
        h.screen.refuseEverything()
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)
        #expect(await eventually { h.screen.commands.count == 1 })

        // A SUCCESSFUL write afterwards is the synchronisation point: its echo
        // cannot arrive before the failed one's catch has already run, so if the
        // failure had echoed it would be sitting in front of this one. Asserting
        // "nothing echoed" straight after the failure would race the catch and
        // pass either way — which is exactly how this test first shipped green
        // against the very mutation it exists to catch.
        h.screen.acceptEverything()
        h.coordinator.hudSliderChanged(to: 0.6)
        #expect(await eventually { applied.last != nil })

        #expect(applied.all.count == 1)
        #expect(applied.last?.value == 0.6)
    }

    @Test func afterAFallbackTheEchoIsCreditedToTheSystem() async {
        // The fallback wrote through the system actuator, so what goes back into
        // the HUD stream has to say so: AppCore routes the echo by authority, and
        // an echo still credited to the neighbour would poke the neighbour's own
        // source — re-drawing a level nobody applied, on the scale the bar is not
        // in. It is also what makes the NEXT drag go straight to the system.
        let h = CoordinatorHarness(withExternalBrightness: true)
        let applied = Applied()
        h.coordinator.onBrightnessApplied = { applied.record($0) }
        h.external?.refuseEverything()
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)

        #expect(await eventually { applied.last != nil })
        #expect(applied.last?.authority == .system)
        #expect(applied.last?.value == 0.8)
    }

    @MainActor
    private final class Applied {
        private(set) var all: [SystemHUD] = []
        var last: SystemHUD? { all.last }
        func record(_ hud: SystemHUD) { all.append(hud) }
    }

    @Test func aNeighbourThatRefusesStillMovesTheScreen() async {
        // Its command channel is a separate setting from its OSD one, so
        // "reports but refuses commands" is a real configuration. A control that
        // does nothing is worse than one writing on the other scale.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)

        #expect(await eventually { h.screen.commands.isEmpty == false })
        #expect(h.screen.commands == [.setBrightness(0.8, display: nil)])
    }

    @Test func aRefusalIsNotAskedAgainEveryFrame() async {
        // Re-asking a neighbour that just refused would stall each frame of the
        // gesture on a deadline.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.8)
        #expect(await eventually { h.screen.commands.count == 1 })
        h.coordinator.hudSliderChanged(to: 0.7)
        #expect(await eventually { h.screen.commands.count == 2 })

        #expect(h.external?.commands.count == 1)   // asked once, then written off
    }

    @Test func aFreshReportEarnsTheNeighbourAnotherChance() async {
        // Recovery by evidence, never by a timer: the app answering again is the
        // proof, and it is the same proof the menu uses.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.hudSliderChanged(to: 0.8)
        #expect(await eventually { h.screen.commands.isEmpty == false })

        h.hudSource.emit(neighbourHUD(0.4))          // it is back
        #expect(await eventually { h.coordinator.state == .hud(neighbourHUD(0.4)) })
        h.coordinator.hudSliderChanged(to: 0.6)

        #expect(await eventually { h.external?.commands.count == 2 })
    }
}
