import Foundation
import Testing
@testable import Crema

/// The one-per-install gate, without a window.
///
/// Standalone and static for the reason the other AppCore seams are: reaching it
/// through an instance means constructing `AppCore`, which boots the real system
/// sources — so the gate that decides whether a person ever sees the tour would
/// be unreachable by any test, and its two rules are exactly the kind that fail
/// silently (a flag written after the window is a tour that comes back forever
/// after a crash; a gate that reads the permission is a tour nobody upgrading
/// ever sees).
@MainActor
struct WelcomeTourPresentationSeamTests {

    /// One isolated, self-cleaning defaults store per test instance.
    private let store = EphemeralDefaults()

    /// The flag is committed BEFORE the window exists, so a crash — or a force
    /// quit — during the tour cannot re-arm it. The closure reads the very
    /// preference the gate just wrote, which is the only way to observe the order
    /// from outside.
    @Test func theFlagIsWrittenBeforeTheWindowIsEverShown() {
        let preferences = Preferences(defaults: store.defaults)
        var flagSeenFromInsideThePresentation: Bool?

        AppCore.presentWelcomeTourIfFirstLaunch(preferences: preferences) {
            flagSeenFromInsideThePresentation = preferences.hasSeenWelcomeTour
        }

        #expect(flagSeenFromInsideThePresentation == true)
        #expect(preferences.hasSeenWelcomeTour)
    }

    @Test func theSecondLaunchPresentsNothing() {
        var presentations = 0

        AppCore.presentWelcomeTourIfFirstLaunch(preferences: Preferences(defaults: store.defaults)) {
            presentations += 1
        }
        // A fresh reader of the same store, the way a second launch arrives: the
        // gate is the persisted flag, never anything held in memory.
        AppCore.presentWelcomeTourIfFirstLaunch(preferences: Preferences(defaults: store.defaults)) {
            presentations += 1
        }

        #expect(presentations == 1)
    }

    /// The deliberate difference from the Accessibility-only onboarding this
    /// replaces: that one asked the permission first and skipped anyone who
    /// already had it. The tour asks nothing. An install arriving from that
    /// version carries its flag set and, very often, the permission granted —
    /// which is precisely the install whose first launch predates every step this
    /// tour exists to walk through, so it is the last one that may be skipped.
    @Test func theLegacyOnboardingFlagDoesNotGateTheTour() {
        store.defaults.set(true, forKey: "hasSeenAccessibilityOnboarding")
        var presented = false

        AppCore.presentWelcomeTourIfFirstLaunch(preferences: Preferences(defaults: store.defaults)) {
            presented = true
        }

        #expect(presented)
    }
}
