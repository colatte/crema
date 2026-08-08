import AppKit
import Testing
@testable import Crema

/// The composition root's lock-surface join, on the same criterion as its
/// siblings in `AppCoreWiringSeamTests`: pin the wiring where a mistake COMPILES,
/// RUNS, and produces a wrong-but-plausible app.
///
/// This suite used to guard TWO opt-in preferences seeded from one call, both
/// `Bool` and neither mentioned in the other's type — the pairing existed
/// because crossing them drew an uninvited window over somebody's lock screen,
/// or made a network request for somebody who declined one. The second
/// preference is gone with the surface that justified it
/// (docs/DECISIONS.md: the-lock-surface-is-a-card), so what remains is the one
/// join that still decides whether a window appears over a lock screen.
///
/// The crossing test could not simply lose its partner: with one boolean there
/// is nothing to cross, and a single-preference assertion is weaker by
/// construction. What replaces it is the state that used to be implicit — a
/// preference OFF must leave the space untouched even while everything else
/// about the surface is ready to build.
@MainActor
struct AppCoreLockScreenSeamTests {

    /// Built already-locked, the way the lifecycle suite does it: `start()`
    /// reconciles synchronously against the mirror, while a `report` afterwards
    /// only lands on the next turn.
    private func lockedPresenter(
        widget: Bool,
        space: RecordingRaisedSpace
    ) -> (LockScreenPresenter, CoordinatorHarness) {
        let defaults = EphemeralDefaults()
        let preferences = Preferences(defaults: defaults.defaults)
        preferences.showsLockScreenWidget = widget

        let harness = CoordinatorHarness()
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let built = AppCore.makeLockScreenPresenter(
            coordinator: harness.coordinator,
            lock: mirror,
            lowPower: LowPowerModeMirror(),
            preferences: preferences,
            space: space
        )
        built.start()
        // The harness is returned so the Coordinator outlives the panel reading it.
        return (built, harness)
    }

    @Test func theWidgetPreferenceDecidesWhetherASurfaceAppears() {
        // Observed through the space rather than a factory spy, because it is the
        // real `makePanel` the seam installs that has to be reached.
        let onSpace = RecordingRaisedSpace()
        let on = lockedPresenter(widget: true, space: onSpace)
        withExtendedLifetime(on) { #expect(!onSpace.adopted.isEmpty) }

        let offSpace = RecordingRaisedSpace()
        let off = lockedPresenter(widget: false, space: offSpace)
        withExtendedLifetime(off) { #expect(offSpace.adopted.isEmpty) }
    }

    @Test func theSurfaceStaysAwayWhileLockedAndUnwanted() {
        // The half that carries the weight now that there is no second preference
        // to cross against: everything the surface needs is present — the session
        // is locked, the space is available, the coordinator is live — and the
        // ONLY thing withholding a window over somebody's lock screen is the
        // preference. A seam that ignored it would pass the pairing above only by
        // accident of ordering; here there is no other candidate cause.
        let space = RecordingRaisedSpace()
        let built = lockedPresenter(widget: false, space: space)
        withExtendedLifetime(built) {
            #expect(space.isAvailable, "the space would have accepted a window")
            #expect(space.adopted.isEmpty, "and none was offered")
        }
    }

    @Test func theWidgetPreferenceIsBornOff() {
        // The surface is a window over a lock screen. It may not arrive by upgrade.
        let defaults = EphemeralDefaults()
        let preferences = Preferences(defaults: defaults.defaults)
        #expect(!preferences.showsLockScreenWidget)
    }
}
