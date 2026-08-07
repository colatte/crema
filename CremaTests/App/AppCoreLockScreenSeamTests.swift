import AppKit
import Testing
@testable import Crema

/// The composition root's lock-surface join, on the same criterion as its
/// siblings in `AppCoreWiringSeamTests`: pin the wiring where a mistake COMPILES,
/// RUNS, and produces a wrong-but-plausible app.
///
/// This seam seeds two opt-in preferences from one call, both `Bool`, neither
/// mentioned in the other's type. Crossing them draws an uninvited window over
/// somebody's lock screen, or makes a network request for somebody who declined
/// one — and every test in the suite stays green.
@MainActor
struct AppCoreLockScreenSeamTests {

    /// Built already-locked, the way the lifecycle suite does it: `start()`
    /// reconciles synchronously against the mirror, while a `report` afterwards
    /// only lands on the next turn.
    private func lockedPresenter(
        widget: Bool,
        artwork: Bool,
        space: RecordingRaisedSpace
    ) -> (LockScreenPresenter, CoordinatorHarness) {
        let defaults = EphemeralDefaults()
        let preferences = Preferences(defaults: defaults.defaults)
        preferences.showsLockScreenWidget = widget
        preferences.fetchesHighResolutionArtwork = artwork

        let harness = CoordinatorHarness()
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let built = AppCore.makeLockScreenPresenter(
            coordinator: harness.coordinator,
            lock: mirror,
            lowPower: LowPowerModeMirror(),
            preferences: preferences,
            space: space,
            // Injected even though nothing here resolves a cover: the production
            // default is a live URLSession client, and a constructor default left
            // blank at a test site is a real network border wired in silently.
            lookup: MockArtworkLookup()
        )
        built.start()
        // The harness is returned so the Coordinator outlives the panel reading it.
        return (built, harness)
    }

    @Test func theWidgetPreferenceDecidesWhetherASurfaceAppears() {
        // Observed through the space rather than a factory spy, because it is the
        // real `makePanel` the seam installs that has to be reached.
        let onSpace = RecordingRaisedSpace()
        let on = lockedPresenter(widget: true, artwork: false, space: onSpace)
        withExtendedLifetime(on) { #expect(!onSpace.adopted.isEmpty) }

        let offSpace = RecordingRaisedSpace()
        let off = lockedPresenter(widget: false, artwork: true, space: offSpace)
        // The pairing is deliberate: this case has the OTHER preference on, so a
        // seam that read the wrong one would build a window here.
        withExtendedLifetime(off) { #expect(offSpace.adopted.isEmpty) }
    }

    @Test func theArtworkPreferenceDecidesWhetherCoversAreFetched() {
        let fetching = lockedPresenter(widget: false, artwork: true, space: RecordingRaisedSpace())
        #expect(fetching.0.artworkLookupIsEnabled)

        let quiet = lockedPresenter(widget: true, artwork: false, space: RecordingRaisedSpace())
        // Same pairing, the other way round. Both halves are needed: a seam that
        // seeded both from `showsLockScreenWidget` passes either one alone.
        #expect(!quiet.0.artworkLookupIsEnabled)
    }

    @Test func bothPreferencesAreBornOff() {
        // The surface is a window over a lock screen and the lookup is a network
        // request naming what you listen to. Neither may arrive by upgrade.
        let defaults = EphemeralDefaults()
        let preferences = Preferences(defaults: defaults.defaults)
        #expect(!preferences.showsLockScreenWidget)
        #expect(!preferences.fetchesHighResolutionArtwork)
    }
}
