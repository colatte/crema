import Foundation
import Testing
@testable import Crema

/// Preferences over an isolated UserDefaults suite, keyed by DisplayUUID.
struct PreferencesTests {

    private let internalDisplay = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")
    private let externalDisplay = DisplayUUID(rawValue: "5B7DEA55-96A6-4F31-9D5B-1D2FCB1AA43C")

    /// One isolated, self-cleaning defaults store per test instance.
    private let store = EphemeralDefaults()

    @Test func styleDefaultsToNotch() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(preferences.style(for: internalDisplay) == .notch)
    }

    /// A persisted rawValue of a removed style ("circular", "pill") — or any
    /// garbage — must degrade to the default, never crash or misdispatch.
    /// Writes the raw key format directly to also pin the persistence format.
    @Test func unknownPersistedStyleDegradesToTheDefault() {
        store.defaults.set("pill", forKey: "style.\(internalDisplay.rawValue)")
        store.defaults.set("circular", forKey: "style.\(externalDisplay.rawValue)")

        let preferences = Preferences(defaults: store.defaults)
        #expect(preferences.style(for: internalDisplay) == .notch)
        #expect(preferences.style(for: externalDisplay) == .notch)
    }

    @Test func styleIsStoredPerDisplayAndPersists() {
        let preferences = Preferences(defaults: store.defaults)

        preferences.setStyle(.card, for: internalDisplay)

        #expect(preferences.style(for: internalDisplay) == .card)
        #expect(preferences.style(for: externalDisplay) == .notch)
        // A fresh instance over the same defaults reads the same value back.
        #expect(Preferences(defaults: store.defaults).style(for: internalDisplay) == .card)
    }

    @Test func showsNowPlayingDefaultsToTheInternalDisplayOnly() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(preferences.showsNowPlaying(on: internalDisplay, isInternal: true))
        #expect(!preferences.showsNowPlaying(on: externalDisplay, isInternal: false))
    }

    @Test func nativeOSDSuppressionDefaultsToOffAndPersists() {
        // Suppression is opt-in — the user activates it.
        let preferences = Preferences(defaults: store.defaults)
        #expect(!preferences.suppressesNativeOSD)

        preferences.suppressesNativeOSD = true

        #expect(Preferences(defaults: store.defaults).suppressesNativeOSD)
    }

    @Test func accessibilityOnboardingFlagDefaultsToFalseAndPersists() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(!preferences.hasSeenAccessibilityOnboarding)

        preferences.hasSeenAccessibilityOnboarding = true

        #expect(Preferences(defaults: store.defaults).hasSeenAccessibilityOnboarding)
    }

    @Test func showsNowPlayingOverridesBeatTheDefaultInBothDirections() {
        let preferences = Preferences(defaults: store.defaults)

        preferences.setShowsNowPlaying(false, on: internalDisplay)
        preferences.setShowsNowPlaying(true, on: externalDisplay)

        #expect(!preferences.showsNowPlaying(on: internalDisplay, isInternal: true))
        #expect(preferences.showsNowPlaying(on: externalDisplay, isInternal: false))
    }

    @Test func nowPlayingBehaviorDefaultsAndPersists() {
        let preferences = Preferences(defaults: store.defaults)
        // Reactive and show-controls default on; include-browsers defaults off.
        #expect(preferences.reactiveNowPlaying)
        #expect(preferences.showsPlaybackControls)
        #expect(!preferences.includesBrowserMedia)

        preferences.reactiveNowPlaying = false
        preferences.showsPlaybackControls = false
        preferences.includesBrowserMedia = true

        let reread = Preferences(defaults: store.defaults)
        #expect(!reread.reactiveNowPlaying)
        #expect(!reread.showsPlaybackControls)
        #expect(reread.includesBrowserMedia)
    }
}
