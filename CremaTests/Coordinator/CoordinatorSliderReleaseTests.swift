import Testing
@testable import Crema

/// The gesture protocol between the level slider and the Coordinator: a change
/// marks a gesture in flight, and the RELEASE is what lets a bar nothing wrote
/// settle back to the last level with evidence behind it
/// (docs/DECISIONS.md: the-bar-never-outruns-the-screen). The drag reports both
/// ends; the accessibility representation reported only the first, so a
/// VoiceOver increment left the app believing a finger was resting on a bar
/// nobody was touching, and the correction waited for a release that could never
/// come.
///
/// The slider's pure rule is pinned here, beside the Coordinator state it
/// protects, rather than among the other slider mechanics: the two halves are
/// one contract and have to fail together.
@MainActor
struct CoordinatorSliderReleaseTests {

    /// A bar the neighbour drew for a monitor that is not the built-in panel —
    /// the one target no actuator in the app writes, so a drag on it can be
    /// declined all the way down.
    private func onExternalDisplay(_ value: Double) -> SystemHUD {
        SystemHUD(
            kind: .screenBrightness, value: value,
            target: .display(DisplayUUID(rawValue: "MONITOR-1")), authority: .betterDisplay
        )
    }

    @Test func anAssistiveAdjustmentReportsTheChangeThenTheRelease() {
        // The order is the contract, not a detail: the change is what marks a
        // gesture in flight, so a release sent ahead of it would be undone by the
        // change arriving behind it — the same stuck state, one step later.
        var reported: [String] = []

        HUDLevelSlider.adjust(
            to: 0.42,
            onChange: { reported.append("changed \($0)") },
            onRelease: { reported.append("released") }
        )

        #expect(reported == ["changed 0.42", "released"])
    }

    @Test func anAssistiveAdjustmentLetsAnUnbackedBarSettle() async {
        // A VoiceOver increment is a whole gesture in one step. Both actuators
        // decline here (the bar names an external display, and the neighbour that
        // drew it has its command channel off), so the level the adjustment asked
        // for is one no display went to — and the settle only runs because the
        // adjustment reported its own end.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()
        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        HUDLevelSlider.adjust(
            to: 0.9,
            onChange: { h.coordinator.hudSliderChanged(to: $0) },
            onRelease: { h.coordinator.hudSliderReleased() }
        )

        // The adjustment really was delivered: a rule that dropped the change
        // instead of the release would leave the bar at 0.5 too, and pass the
        // assertion below for the opposite reason.
        #expect(await eventually { h.screen.commands.count == 1 })
        #expect(h.screen.commands == [.setBrightness(0.9, display: DisplayUUID(rawValue: "MONITOR-1"))])
        #expect(await eventually { h.coordinator.state == .hud(onExternalDisplay(0.5)) })
    }

    @Test func aChangeWithNoReleaseHoldsTheBarOnALevelNothingWrote() async {
        // The control that names the bug the rule above closes, and the reason
        // the release cannot be inferred from the values: a change reported on its
        // own is indistinguishable from a finger resting mid-drag, and a resting
        // finger is precisely what must NOT be corrected under the pointer.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()
        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)

        #expect(await eventually { h.screen.commands.count == 1 })   // both declined
        await settle()
        #expect(h.coordinator.state == .hud(onExternalDisplay(0.9)))
    }
}
