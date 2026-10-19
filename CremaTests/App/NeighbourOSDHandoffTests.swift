import Testing
@testable import Crema

/// The handoff of a neighbour's own indicator, over an in-memory neighbour. What
/// has to hold: only what Crema changed is handed back, and only while it reads as
/// Crema left it; the original is on disk before the write leaves; silence keeps
/// what is owed; and the quit hands back whatever the intent.
@MainActor
struct NeighbourOSDHandoffTests {

    /// Whether the neighbour is running, flipped by a test after the handoff
    /// has captured the reading.
    @MainActor
    private final class Neighbour {
        var running = true
    }

    @MainActor
    private struct Harness {
        let store = EphemeralDefaults()
        let preferences: Preferences
        let channel: MockOSDSettingsChannel
        let neighbour = Neighbour()
        let handoff: NeighbourOSDHandoff

        /// The neighbour as it ships: dispatch off, its own indicator on.
        init(dispatches: Bool = false, showsOwn: Bool = true) {
            preferences = Preferences(defaults: store.defaults)
            channel = MockOSDSettingsChannel([.dispatchesToOtherApps: dispatches, .showsOwnIndicator: showsOwn])
            let neighbour = neighbour
            handoff = NeighbourOSDHandoff(
                channel: channel,
                preferences: preferences,
                isNeighbourRunning: { neighbour.running }
            )
        }

        var owed: [NeighbourOSDSetting: Bool] {
            Dictionary(uniqueKeysWithValues: NeighbourOSDSetting.allCases.compactMap { setting in
                preferences.neighbourOSDOriginal(setting).map { (setting, $0) }
            })
        }
    }

    @Test func takingOverTurnsDispatchOnBeforeTheOwnIndicatorOff() async {
        let h = Harness()
        h.handoff.setWanted(true)

        #expect(await eventually { h.handoff.status == .inPlace })
        #expect(h.channel.values == [.dispatchesToOtherApps: true, .showsOwnIndicator: false])
        // Dispatch first, so no press in between is left with neither indicator.
        #expect(h.channel.writes == [.write(.dispatchesToOtherApps, true), .write(.showsOwnIndicator, false)])
        #expect(h.owed == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])
    }

    @Test func aSwitchAlreadyAsNeededIsNeitherWrittenNorOwed() async {
        // The user had dispatch on before Crema ever ran: it is theirs, so a
        // hand-back must never turn it off.
        let h = Harness(dispatches: true)
        h.handoff.setWanted(true)

        #expect(await eventually { h.handoff.status == .inPlace })
        #expect(h.channel.writes == [.write(.showsOwnIndicator, false)])
        #expect(h.owed == [.showsOwnIndicator: true])

        await h.handoff.handBackBeforeQuitting()
        #expect(h.channel.values == [.dispatchesToOtherApps: true, .showsOwnIndicator: true])
    }

    @Test func theOriginalIsOnDiskBeforeTheWriteLeaves() async {
        // The neighbour persists the write itself, so a Crema that dies between
        // the write and the record would leave a change nobody knows to undo.
        let h = Harness()
        var recordedWhenSent: [NeighbourOSDSetting: Bool?] = [:]
        let preferences = h.preferences
        h.channel.onWrite = { setting, _ in recordedWhenSent[setting] = preferences.neighbourOSDOriginal(setting) }

        h.handoff.setWanted(true)

        #expect(await eventually { h.handoff.status == .inPlace })
        #expect(recordedWhenSent == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])
    }

    @Test func quittingHandsBackInReverseAndOwesNothing() async {
        let h = Harness()
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .inPlace })

        await h.handoff.handBackBeforeQuitting()

        #expect(h.channel.values == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])
        // Its own indicator back first, so no press in between is left with neither.
        #expect(h.channel.writes.suffix(2) == [.write(.showsOwnIndicator, true), .write(.dispatchesToOtherApps, false)])
        #expect(h.owed.isEmpty)
        #expect(h.handoff.status == .idle)
    }

    @Test func aSwitchTheUserFlippedWhileHeldIsTheirs() async {
        let h = Harness()
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .inPlace })

        // The user turns the neighbour's indicator back on in its own window.
        h.channel.values[.showsOwnIndicator] = true
        await h.handoff.handBackBeforeQuitting()

        #expect(h.channel.writes.count == 3)
        #expect(h.channel.writes.last == .write(.dispatchesToOtherApps, false))
        #expect(h.channel.values[.showsOwnIndicator] == true)
        #expect(h.owed.isEmpty)
    }

    @Test func silenceKeepsWhatIsOwedAndTheNextEdgePaysIt() async {
        let h = Harness()
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .inPlace })

        h.channel.failure = .unanswered
        h.handoff.setWanted(false)
        #expect(await eventually { h.handoff.status == .unanswered })
        #expect(h.owed == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])

        // The neighbour answers again (it launched, say): the debt is paid then.
        h.channel.failure = nil
        h.handoff.reconcile()
        #expect(await eventually { h.handoff.status == .idle && h.owed.isEmpty })
        #expect(h.channel.values == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])
    }

    @Test func aNeighbourThatQuitsLeavesNoAdviceBehind() async {
        // "Isn't responding, turn this on" about an app that is simply closed
        // sends the person to a window that is not there.
        let h = Harness()
        h.channel.failure = .unanswered
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .unanswered })

        h.neighbour.running = false
        h.handoff.neighbourTerminated()

        #expect(h.handoff.status == .idle)
    }

    @Test func silenceFromANeighbourThatQuitMidPassIsNotUnresponsiveness() async {
        // The termination can be heard while the deadline still runs; the pass
        // that ends after it must not bring the stale verdict back.
        let h = Harness()
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .inPlace })

        h.channel.failure = .unanswered
        let neighbour = h.neighbour
        h.channel.onRead = { _ in neighbour.running = false }
        h.handoff.reconcile()

        // Leaving `.inPlace` is the pass's end either way; where it lands is the claim.
        #expect(await eventually { h.handoff.status != .inPlace })
        #expect(h.handoff.status == .idle)
    }

    @Test func aWriteThatDoesNotTakeIsARefusal() async {
        // An accepted request is not a landed value (BetterDisplay Guide: "an
        // accepted request [does not prove] a physical device completed the
        // change"); the read-back is the verdict.
        let h = Harness()
        h.channel.ignoresWrites = true
        h.handoff.setWanted(true)

        #expect(await eventually { h.handoff.status == .refused })
    }

    @Test func aNeighbourThatIsNotRunningIsNotAsked() async {
        let h = Harness()
        h.neighbour.running = false
        h.handoff.setWanted(true)
        h.neighbour.running = true
        h.handoff.reconcile()

        #expect(await eventually { h.handoff.status == .inPlace })
        // Exactly one take-over's requests: the pass that found nobody running
        // asked nothing, where each unanswered request would cost a deadline.
        #expect(h.channel.calls == [
            .read(.dispatchesToOtherApps), .write(.dispatchesToOtherApps, true), .read(.dispatchesToOtherApps),
            .read(.showsOwnIndicator), .write(.showsOwnIndicator, false), .read(.showsOwnIndicator),
        ])
    }

    @Test func aLaunchAfterACrashPaysWhatWasOwed() async {
        // The last session took the neighbour's indicator and never handed it
        // back; this one starts with the switch off.
        let h = Harness(dispatches: true, showsOwn: false)
        h.preferences.setNeighbourOSDOriginal(true, for: .showsOwnIndicator)

        h.handoff.setWanted(false)

        #expect(await eventually { h.owed.isEmpty })
        #expect(h.channel.values == [.dispatchesToOtherApps: true, .showsOwnIndicator: true])
        #expect(h.channel.writes == [.write(.showsOwnIndicator, true)])
    }

    @Test func aWantArrivingDuringTheQuitIsIgnored() async {
        // An unlock or a neighbour launch can land while the quit is handing back;
        // taking the indicator again then would leave it off past the exit.
        let h = Harness()
        h.handoff.setWanted(true)
        #expect(await eventually { h.handoff.status == .inPlace })
        let handoff = h.handoff
        h.channel.onWrite = { _, _ in handoff.setWanted(true) }

        await h.handoff.handBackBeforeQuitting()

        #expect(h.channel.values == [.dispatchesToOtherApps: false, .showsOwnIndicator: true])
        #expect(h.owed.isEmpty)
    }

    @Test func theLatestIntentWinsWithoutFlapping() async {
        // The switch flips on and off before any pass runs, with a debt left from
        // a crash: one pass reads the latest intent and pays it, and never takes
        // the indicator over on the way.
        let h = Harness(showsOwn: false)
        h.preferences.setNeighbourOSDOriginal(true, for: .showsOwnIndicator)
        h.handoff.setWanted(true)
        h.handoff.setWanted(false)

        #expect(await eventually { h.owed.isEmpty })
        #expect(h.channel.writes == [.write(.showsOwnIndicator, true)])
    }
}
