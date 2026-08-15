import Foundation
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

    /// A bar the neighbour drew for a monitor that is not the built-in panel —
    /// the only target no system actuator will take.
    private func onExternalDisplay(_ value: Double) -> SystemHUD {
        SystemHUD(
            kind: .screenBrightness, value: value,
            target: .display(DisplayUUID(rawValue: "MONITOR-1")), authority: .betterDisplay
        )
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

    @Test func theEchoCarriesWhatWasWrittenNotWhatWasAsked() async {
        // Reported on hardware: a fast drag on the bar drawn on the external
        // monitor flicked backwards for an instant before catching up. The
        // neighbour's writer coalesces latest-wins, so the call that DRIVES stays
        // in its drain loop putting newer values on the wire and comes back
        // holding an argument several frames old. Echoing that argument re-draws
        // the bar at a level the drag already left behind, and the next frame
        // yanks it forward again — a bar disagreeing with the finger that moves
        // it. What the actuator reports is the only number that was ever on the
        // wire.
        let h = CoordinatorHarness(withExternalBrightness: true)
        let applied = Applied()
        h.coordinator.onBrightnessApplied = { applied.record($0) }
        h.external?.reportsWritten(0.9)
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.1)

        #expect(await eventually { applied.last != nil })
        #expect(applied.last?.value == 0.9)
        #expect(applied.last?.authority == .betterDisplay)
        // The command still carries the frame's own value: only the ECHO is
        // rewritten, and an actuator asked for something else would be a
        // different bug.
        #expect(h.external?.commands == [.setBrightness(0.1, display: nil)])
    }

    @Test func theFallbackEchoAlsoCarriesWhatTheSystemWrote() async {
        // Same rule one actuator down. The fallback path re-credits the echo to
        // the system, and re-crediting is exactly the kind of rewrite that
        // invites putting the argument back in place of the written value.
        let h = CoordinatorHarness(withExternalBrightness: true)
        let applied = Applied()
        h.coordinator.onBrightnessApplied = { applied.record($0) }
        h.external?.refuseEverything()
        h.screen.reportsWritten(0.7)
        h.hudSource.emit(neighbourHUD())
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.2)

        #expect(await eventually { applied.last != nil })
        #expect(applied.last?.value == 0.7)
        #expect(applied.last?.authority == .system)
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

    @Test func aDragNothingHonouredComesBackWhenTheHandLetsGo() async {
        // The one arrangement where BOTH actuators decline: the bar names an
        // external display (so DisplayServices refuses it by design, never DDC of
        // our own) and the neighbour that drew it has its command channel off —
        // two separate settings in that app, so this is a configuration a person
        // can really be in. Nothing wrote, so the level under the finger is a
        // level no display went to, and a control that did nothing must not look
        // like one that worked.
        //
        // Not corrected on the spot: the failure lands while the hand is usually
        // still down, and a fill that snaps backwards under the pointer is dragged
        // forward again on the next frame, sixty times a second. It waits for the
        // gesture to end, then eases home — the rejected drag animating back, the
        // way a drop the system will not take does.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()
        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)
        #expect(await eventually { h.screen.commands.count == 1 })   // the fallback declined too
        await settle()

        // Still under the finger, still where the finger put it.
        #expect(h.coordinator.state == .hud(onExternalDisplay(0.9)))

        h.coordinator.hudSliderReleased()

        #expect(await eventually { h.coordinator.state == .hud(onExternalDisplay(0.5)) })
    }

    @Test func aDragThatLandedIsNeverPulledBack() async {
        // The correction reads the same state a working drag does, so a bar that
        // was honoured has to be left exactly where it was dropped. Releasing is
        // the moment it could be undone, so releasing is where this is asserted.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.hudSource.emit(neighbourHUD(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)
        #expect(await eventually { h.external?.commands.count == 1 })
        h.coordinator.hudSliderReleased()
        await settle()

        #expect(h.coordinator.state == .hud(neighbourHUD(0.9)))
    }

    @Test func aTapThatWroteNothingCorrectsItselfWhenTheAnswerLandsLate() async {
        // The hand can be gone before the answer is. A tap releases in a frame or
        // two while the write it fired is still in flight, so by the time the
        // refusal comes back the release that would have corrected the bar has
        // already happened. Nothing is holding the bar then, so the failure
        // corrects it itself — otherwise the quickest gesture is the one that
        // leaves the lie on screen, and it is the gesture a dead control invites,
        // since a tap is what a person tries first.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()
        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })

        // Synchronous, with no await between: both actuators are still to answer.
        h.coordinator.hudSliderChanged(to: 0.9)
        h.coordinator.hudSliderReleased()

        #expect(await eventually { h.coordinator.state == .hud(onExternalDisplay(0.5)) })
    }

    @Test func aPendingCorrectionDoesNotOutliveTheBarItWasFor() async {
        // The HUD dismisses on its own timer, and it can do that with the button
        // still down — the finger is on the bar, not on a mouse the app tracks. A
        // correction still owed when the bar goes away has nothing left to correct,
        // and carrying it forward is worse than dropping it: the NEXT bar is a
        // fresh reading, so the stale mark would fire on the next release and pull
        // a perfectly good drag back to a level two readings old, while its own
        // write was still in flight. So the dismissal clears both the correction
        // and the belief that a finger is down.
        let h = CoordinatorHarness(withExternalBrightness: true)
        h.external?.refuseEverything()
        h.screen.refuseEverything()
        h.hudSource.emit(onExternalDisplay(0.5))
        #expect(await eventually { h.coordinator.state != .hidden })
        h.coordinator.hudSliderChanged(to: 0.9)
        #expect(await eventually { h.screen.commands.count == 1 })   // owed a correction

        await h.clock.waitForSleep(delay: Coordinator.defaultHUDRevertDelay)
        h.clock.advance(delay: Coordinator.defaultHUDRevertDelay)
        #expect(await eventually { h.coordinator.state == .hidden })

        // A new bar, on a display both actuators can write, and a release that
        // beats its answer back.
        h.external?.acceptEverything()
        h.screen.acceptEverything()
        h.hudSource.emit(neighbourHUD(0.3))
        #expect(await eventually { h.coordinator.state == .hud(neighbourHUD(0.3)) })
        h.coordinator.hudSliderChanged(to: 0.8)
        h.coordinator.hudSliderReleased()
        await settle()

        #expect(h.coordinator.state == .hud(neighbourHUD(0.8)))   // never yanked to 0.5
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

    /// The neighbour's real actuator answers a queued drag frame IMMEDIATELY,
    /// before anything reaches the wire, and can fail holding a frame nobody else
    /// will write. The plain mock cannot say either of those things, so the pins
    /// on that seam wire a Coordinator by hand around a coalescing fake — the
    /// same mocks as the harness everywhere else, every clock injected.
    @MainActor
    private struct CoalescingHarness {
        let hudSource = MockSystemHUDSource()
        let screen = MockScreenBrightnessController()
        let external = FakeCoalescingBrightnessController()
        let clock = TestSleepClock()
        let coordinator: Coordinator

        /// `alsoHearing` merges a second HUD source in, the way production merges
        /// the neighbour's — for the test that needs the app's own echo to come
        /// back round through the stream.
        init(alsoHearing extra: (any SystemHUDSource)? = nil) {
            let hud: any SystemHUDSource
            if let extra { hud = MergedSystemHUDSource([hudSource, extra]) } else { hud = hudSource }
            coordinator = Coordinator(
                nowPlayingSource: MockNowPlayingSource(),
                systemHUDSource: hud,
                nowPlayingController: MockNowPlayingController(),
                volumeController: MockVolumeController(),
                screenBrightnessController: screen,
                keyboardBrightnessController: MockKeyboardBrightnessController(),
                externalScreenBrightnessController: external,
                clock: clock
            )
            coordinator.start()
        }
    }

    /// Answers each call from a script: a coalesced echo, a written level, or a
    /// failure carrying an orphan — the three answers the real coalescing writer
    /// can give, produced without a queue since what is under test is what the
    /// Coordinator does with each one.
    private final class FakeCoalescingBrightnessController:
    CoalescingScreenBrightnessWriting, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [Result<BrightnessWriteEcho, BrightnessWriteFailure>] = []
        private var recorded: [CoalescedWrite] = []

        var commands: [CoalescedWrite] { lock.withLock { recorded } }
        func answers(_ next: Result<BrightnessWriteEcho, BrightnessWriteFailure>) {
            lock.withLock { script.append(next) }
        }

        func applyBrightness(_ value: Double, on display: DisplayUUID?) async throws -> BrightnessWriteEcho {
            let next = lock.withLock { () -> Result<BrightnessWriteEcho, BrightnessWriteFailure>? in
                recorded.append(.setBrightness(value, display: display))
                return script.isEmpty ? nil : script.removeFirst()
            }
            switch next {
            case .success(let echo): return echo
            case .failure(let failure): throw failure
            case nil: return .written(value)   // off-script, a write is the plain answer
            }
        }

        func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
            switch try await applyBrightness(value, on: display) {
            case .written(let level), .coalesced(let level): return level
            }
        }
    }

    @Test func theFallbackWritesTheFrameTheChannelOrphanedNotTheOldArgument() async {
        // The drive that fails has been inside its drain for a round-trip, and the
        // finger has moved on: newer frames coalesced behind it, echoed, and were
        // never written. The failure carries the newest of them, and THAT level —
        // on the display it was aimed at — is what the fallback owes the user;
        // writing the drive's own argument would land the screen on a level the
        // finger merely passed through.
        let h = CoalescingHarness()
        h.external.answers(.failure(BrightnessWriteFailure(
            underlying: MockScreenBrightnessController.Refusal(),
            orphan: .init(value: 0.9, display: nil)
        )))
        h.hudSource.emit(SystemHUD(kind: .screenBrightness, value: 0.5, authority: .betterDisplay))
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.3)   // the drive's stale argument

        #expect(await eventually { h.screen.commands.isEmpty == false })
        #expect(h.screen.commands == [.setBrightness(0.9, display: nil)])
    }

    @Test func aCoalescedEchoAloneIsNeverEvidenceForTheSettle() async {
        // A coalesced answer arrives BEFORE anything reaches the wire — it exists
        // so the bar follows the finger, and that is all it may do. Recording it
        // as a confirmed write is how a bar once settled, after a failed gesture,
        // on a level no display ever went to: the echo had promised 0.9, nobody
        // wrote it, and the rollback took the promise for evidence.
        let h = CoalescingHarness()
        let applied = Applied()
        h.coordinator.onBrightnessApplied = { applied.record($0) }
        h.external.answers(.success(.coalesced(0.9)))
        h.external.answers(.failure(BrightnessWriteFailure(
            underlying: MockScreenBrightnessController.Refusal(), orphan: nil
        )))
        h.screen.refuseEverything()   // the fallback declines too: nothing wrote
        let bar = SystemHUD(kind: .screenBrightness, value: 0.5, authority: .betterDisplay)
        h.hudSource.emit(bar)
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)   // answered by the coalesced echo
        #expect(await eventually { applied.last?.value == 0.9 })   // the bar got its echo
        h.coordinator.hudSliderChanged(to: 0.8)   // fails; the fallback refuses
        #expect(await eventually { h.screen.commands.count == 1 })
        h.coordinator.hudSliderReleased()

        // Home is 0.5 — the reading that arrived on its own. Settling on 0.9
        // would mean the echo was taken for a write.
        #expect(await eventually { h.coordinator.state == .hud(bar.at(0.5)) })
    }

    @Test func aCoalescedEchoStaysNoEvidenceAfterTheRoundTripThroughTheHUDStream() async {
        // The twin of the test above with the loop CLOSED the way production
        // closes it: the neighbour's source yields the app's own echo back into
        // the HUD stream (`AppCore.wireBrightnessEcho` → `noteApplied`), and it
        // arrives at `handleHUDUpdate` on the same path a spontaneous report
        // takes. Recorded there as a reading, the promised 0.9 became "confirmed"
        // one hop later than the guard in `writeThroughNeighbour` could see, and
        // the rollback settled the bar on it. Only the loop shows that.
        let neighbour = BetterDisplayOSDSource(target: { _ in nil })
        let h = CoalescingHarness(alsoHearing: neighbour)
        AppCore.wireBrightnessEcho(
            to: h.coordinator, screen: SpySampledSource(), keyboard: SpySampledSource(), neighbour: neighbour
        )
        h.external.answers(.success(.coalesced(0.9)))
        h.external.answers(.failure(BrightnessWriteFailure(
            underlying: MockScreenBrightnessController.Refusal(), orphan: nil
        )))
        h.screen.refuseEverything()
        let bar = SystemHUD(kind: .screenBrightness, value: 0.5, authority: .betterDisplay)
        h.hudSource.emit(bar)
        #expect(await eventually { h.coordinator.state != .hidden })

        h.coordinator.hudSliderChanged(to: 0.9)   // the coalesced echo goes round the loop
        #expect(await eventually { h.coordinator.state == .hud(bar.at(0.9).echoed()) })   // and moves the bar
        h.coordinator.hudSliderChanged(to: 0.8)   // fails; the fallback refuses
        #expect(await eventually { h.screen.commands.count == 1 })
        h.coordinator.hudSliderReleased()

        // Home is still 0.5: the echo that came back through the stream moved the
        // bar and was not taken for a reading.
        #expect(await eventually { h.coordinator.state == .hud(bar.at(0.5)) })
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

/// What the scripted coalescing fake records per call; file-scoped because the
/// house lint caps type nesting at one level.
private enum CoalescedWrite: Equatable {
    case setBrightness(Double, display: DisplayUUID?)
}
