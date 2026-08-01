import Observation
import Testing
@testable import Crema

/// The composition root's join between the Low Power Mode source and the mirror
/// the skins read through the environment. Both halves are proven on their own —
/// the source re-reads and emits, the glyph's rule vetoes on the flag — and
/// neither says the app connects one to the other.
///
/// The seam is a static for the reason every other `wire*` in the composition root
/// is: reaching it through an instance means constructing `AppCore`, which boots
/// the real system sources.
@MainActor
struct LowPowerModeWiringTests {

    @Test func theMirrorIsSeededFromTheAuthoritativeReadBeforeAnyEdge() {
        // The launch case has no edge to ride: a Mac already in Low Power Mode
        // posts nothing, so a wiring that only followed the stream would leave the
        // waveform pulsing until the user toggled the system setting twice. The
        // assertion is synchronous on purpose — the seed happens while wiring,
        // not on the consuming task's first turn.
        let source = MockLowPowerModeSource(lowPower: true)
        let mirror = LowPowerModeMirror()

        let task = AppCore.wireLowPowerMode(source: source, into: mirror)

        #expect(mirror.isLowPower)
        task.cancel()
    }

    @Test func theMirrorFollowsTheSourceInBothDirections() async {
        // Both directions are load-bearing: a mirror that never fills leaves the
        // bars dancing through Low Power Mode, and one that never clears freezes
        // them for the rest of the session once it ends.
        let source = MockLowPowerModeSource(lowPower: false)
        let mirror = LowPowerModeMirror()
        let task = AppCore.wireLowPowerMode(source: source, into: mirror)
        #expect(!mirror.isLowPower)

        source.set(true)
        #expect(await eventually { mirror.isLowPower })

        source.set(false)
        #expect(await eventually { !mirror.isLowPower })

        task.cancel()
    }

    @Test func aRealTransitionInvalidatesObserversEvenWithADuplicateAheadOfIt() async {
        // The mirror is read from view bodies, and the source emits on every
        // power-source change (unplugging the charger with Low Power Mode
        // untouched), so unchanged reports are the ordinary case. The guarded
        // write is CONTRACT, not something this suite can pin: the house measured
        // that an equal-value write to an @Observable property does not
        // invalidate on its own (recorded at DisplayRosterTests), so a "nothing
        // invalidated" assertion here would stay green with the guard deleted —
        // and the earlier draft of this test asserted exactly that behind a
        // yield-count settle, the negative-without-a-barrier shape the TDD rules
        // forbid. What CAN be pinned is that a duplicate sitting ahead of a real
        // transition on the same ordered stream does not swallow it.
        let source = MockLowPowerModeSource(lowPower: false)
        let mirror = LowPowerModeMirror()
        let task = AppCore.wireLowPowerMode(source: source, into: mirror)

        let changed = Flag()
        withObservationTracking {
            _ = mirror.isLowPower
        } onChange: {
            changed.value = true
        }

        source.set(false)
        source.set(true)
        #expect(await eventually { changed.value })
        #expect(await eventually { mirror.isLowPower })

        task.cancel()
    }
}
