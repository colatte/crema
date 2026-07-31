import Foundation
import Testing
@testable import Crema

/// The composition root's own joins. Everything these seams connect is proven in
/// isolation elsewhere — the suppressor fires its callbacks, each sampler spends
/// its window, the Coordinator echoes what it applied — and none of that says the
/// app hooks the right end to the right end. An audit of the App layer found 224
/// wiring points with 181 unpinned; these are the ones where a mis-wire COMPILES,
/// RUNS, and produces a wrong-but-plausible app rather than a crash or a type
/// error. The rest are recorded as an accepted gap in CLAUDE.md.
///
/// The sibling suite AppCoreHandbackWiringTests measured the whole class: deleting
/// one arm of the hand-back switch left all 900-odd tests green.
@MainActor
struct AppCoreWiringSeamTests {

    /// The counters as one value, so an assertion names every collaborator at
    /// once — a sampler poked when a DIFFERENT one should have been is invisible
    /// to an assertion that only looks at the one it expected.
    private struct Pokes: Equatable {
        let screen: Int, keyboard: Int, volume: Int
    }

    /// What the neighbour source emitted, collected on the actor the test asserts
    /// from — the stream is consumed by a Task, so a plain local var would be a
    /// non-Sendable capture crossing an isolation boundary.
    @MainActor
    private final class Reported {
        private(set) var all: [SystemHUD] = []
        func append(_ hud: SystemHUD) { all.append(hud) }
    }

    /// Counts both directions separately: a sampler poked when it should have
    /// stood down is a different bug from one that is never poked at all.
    private final class RecordingSampler: ManuallySampledSource, @unchecked Sendable {
        private let lock = NSLock()
        private var _sampled = 0
        private var _stoodDown = 0
        var sampled: Int { lock.withLock { _sampled } }
        var stoodDown: Int { lock.withLock { _stoodDown } }
        func sample() { lock.withLock { _sampled += 1 } }
        func standDown() { lock.withLock { _stoodDown += 1 } }
    }

    // MARK: - The post-apply poke

    @Test func eachAppliedKeyPokesItsOwnSamplerAndNoOther() {
        // With the key consumed, the app's write lands AFTER the router's key-time
        // sample, so the HUD would sit on the pre-apply value without this.
        let suppressor = RecordingOSDSuppressor()
        let screen = RecordingSampler(), keyboard = RecordingSampler(), volume = RecordingSampler()
        AppCore.wireApplyPoke(from: suppressor, screen: screen, keyboard: keyboard, volume: volume)
        var taken: Pokes { Pokes(screen: screen.sampled, keyboard: keyboard.sampled, volume: volume.sampled) }

        suppressor.onApplied?(.screenBrightnessUp)
        #expect(taken == Pokes(screen: 1, keyboard: 0, volume: 0))

        suppressor.onApplied?(.keyboardBrightnessDown)
        #expect(taken == Pokes(screen: 1, keyboard: 1, volume: 0))

        // The arm that reads most deletable and is the one that must not go: its
        // own comment says Core Audio echoes volume anyway, which is true
        // everywhere EXCEPT the scale boundary, where a consumed key writes
        // nothing and fires no echo at all. Folded into the mute arm, the app
        // swallows a key and draws nothing — a consumed key always owes feedback.
        suppressor.onApplied?(.volumeUp)
        #expect(taken == Pokes(screen: 1, keyboard: 1, volume: 1))

        // Mute is a real toggle and Core Audio always echoes it; poking here would
        // be a second reading for one press.
        suppressor.onApplied?(.mute)
        #expect(taken == Pokes(screen: 1, keyboard: 1, volume: 1))
    }

    // MARK: - The escalation mirror the menu reads

    @Test func theMenuMirrorFollowsTheSuppressorInBothDirections() {
        // This closure is the only path from an escalation to the user: the menu's
        // warning and its "try to reactivate now" button both hang off what the
        // monitor holds. Frozen empty, the user's keys go quietly back to the
        // system while the menu reports health and the repair button never
        // appears; frozen full, a healed domain leaves a permanent false warning.
        let suppressor = RecordingOSDSuppressor()
        let monitor = OSDSuppressionMonitor()
        AppCore.wireSuspensionMirror(from: suppressor, to: monitor)

        suppressor.setLongSuspended([.volume])
        #expect(monitor.longSuspendedDomains == [.volume])

        suppressor.setLongSuspended([.volume, .screenBrightness])
        #expect(monitor.longSuspendedDomains == [.volume, .screenBrightness])

        // Recovery is the direction a value-captured closure gets wrong quietly:
        // the set is RE-READ at fire time, never sampled into the closure when it
        // was wired.
        suppressor.setLongSuspended([])
        #expect(monitor.longSuspendedDomains.isEmpty)
    }

    // MARK: - The brightness echo, routed by authority

    @Test func theBrightnessEchoGoesToWhoeverHasTheScaleItWasWrittenOn() async {
        // A drag reports what it applied, and which of the three collaborators
        // hears it decides whether the bar stays honest. The neighbour's level is
        // on ITS scale and it does not publish OSD for changes third parties
        // request, so its echo must be handed straight back to it; ours is a
        // re-read of the panel. Cross the two and a drag on the neighbour's bar
        // re-reads the built-in panel — a different scale, measured at 0.625
        // against 0.504 on the same screen — so the fill jumps under the finger.
        let coordinator = CoordinatorHarness().coordinator
        let screen = RecordingSampler(), keyboard = RecordingSampler()
        // An injected target keeps the source from installing its distributed
        // observer, so this touches no system notification centre.
        let neighbour = BetterDisplayOSDSource(target: { _ in nil })
        let seen = Reported()
        let task = Task { @MainActor in for await hud in neighbour.updates { seen.append(hud) } }
        AppCore.wireBrightnessEcho(
            to: coordinator, screen: screen, keyboard: keyboard, neighbour: neighbour
        )
        var taken: Pokes { Pokes(screen: screen.sampled, keyboard: keyboard.sampled, volume: 0) }

        coordinator.onBrightnessApplied?(
            SystemHUD(kind: .screenBrightness, value: 0.4, authority: .betterDisplay)
        )
        #expect(await eventually { !seen.all.isEmpty })
        #expect(seen.all.last?.value == 0.4)
        #expect(taken == Pokes(screen: 0, keyboard: 0, volume: 0))   // neither of ours

        coordinator.onBrightnessApplied?(SystemHUD(kind: .screenBrightness, value: 0.4))
        #expect(taken == Pokes(screen: 1, keyboard: 0, volume: 0))

        coordinator.onBrightnessApplied?(SystemHUD(kind: .keyboardBrightness, value: 0.4))
        #expect(taken == Pokes(screen: 1, keyboard: 1, volume: 0))

        // Volume never routes here — Core Audio echoes itself.
        coordinator.onBrightnessApplied?(SystemHUD(kind: .volume, value: 0.4))
        #expect(taken == Pokes(screen: 1, keyboard: 1, volume: 0))
        #expect(seen.all.count == 1)

        task.cancel()
    }

    // MARK: - The neighbour source's local sibling

    @Test func theNeighbourSourceSilencesTheScreenSourceAndNotTheKeyboardOne() {
        // `onReport` carries a default of {}, so dropping it — or handing it the
        // keyboard source, the other one in scope at the call site — compiles in
        // silence. What breaks is a whole press: with suppression off, this app's
        // tap merely OBSERVES the brightness key and arms its own poll while the
        // neighbour is the one applying and reporting, so two bars draw for one
        // press and the wrong value lands last.
        let screen = RecordingSampler(), keyboard = RecordingSampler()
        let source = AppCore.makeNeighbourSource(
            target: { _ in .display(DisplayUUID(rawValue: "MONITOR-1")) },
            standingDown: screen
        )

        source.handle(
            json: #"{"controlTarget":"combinedBrightness","displayID":1,"maxValue":64,"systemIconID":1,"value":48}"#
        )

        #expect(screen.stoodDown == 1)
        #expect(keyboard.stoodDown == 0)
    }
}
