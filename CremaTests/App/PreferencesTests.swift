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
    /// garbage — is no override at all: with nothing declared it degrades to the
    /// shipped default, never crashing or misdispatching (the same rawValue
    /// falling through to a DECLARED style is pinned separately below). Writes
    /// the raw key format directly to also pin the persistence format.
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

    @Test func styleFallsBackToTheDeclarationAndTheOverrideBeatsIt() {
        let preferences = Preferences(defaults: store.defaults)
        preferences.declaredStyle = .classic

        // No override anywhere: every display — including one this install has
        // never seen, which is the display plugged in later — reads the
        // declaration instead of the shipped default.
        #expect(preferences.style(for: internalDisplay) == .classic)
        #expect(preferences.style(for: externalDisplay) == .classic)

        preferences.setStyle(.card, for: internalDisplay)

        #expect(preferences.style(for: internalDisplay) == .card)
        #expect(preferences.style(for: externalDisplay) == .classic)
    }

    @Test func theStyleDeclarationDefaultsToNotchAndPersists() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(preferences.declaredStyle == .notch)

        preferences.declaredStyle = .card

        #expect(Preferences(defaults: store.defaults).declaredStyle == .card)
    }

    /// An override holding a style removed since ("pill") is no override at all:
    /// it falls through to the DECLARATION, never to the shipped default the user
    /// replaced. Writes the raw key to also pin the persistence format.
    @Test func anUnknownOverrideFallsThroughToTheDeclaration() {
        let preferences = Preferences(defaults: store.defaults)
        preferences.declaredStyle = .classic
        store.defaults.set("pill", forKey: "style.\(internalDisplay.rawValue)")

        #expect(preferences.style(for: internalDisplay) == .classic)
    }

    @Test func declaringAStyleEverywhereDropsEveryOverrideAndSparesOtherPreferences() {
        let preferences = Preferences(defaults: store.defaults)
        // Overrides written the way the old all-displays writer did — one of
        // these displays stands for a monitor not attached right now.
        preferences.setStyle(.notch, for: internalDisplay)
        preferences.setStyle(.card, for: externalDisplay)
        preferences.setShowsNowPlaying(false, on: internalDisplay)
        preferences.hudIndicatorStyle = .filled

        preferences.declareStyleEverywhere(.classic)

        #expect(preferences.declaredStyle == .classic)
        #expect(preferences.style(for: internalDisplay) == .classic)
        #expect(preferences.style(for: externalDisplay) == .classic)
        // The sweep is prefix-scoped: it must not take the per-display
        // now-playing key, the indicator style, or the declaration itself.
        #expect(!preferences.showsNowPlaying(on: internalDisplay, isInternal: true))
        #expect(preferences.hudIndicatorStyle == .filled)
        #expect(Preferences(defaults: store.defaults).declaredStyle == .classic)
    }

    @Test func theDeclarationIsAdoptedFromALegacyOverrideOnce() {
        // A pre-declaration install: only per-display keys exist, and the
        // internal display — the one the picker speaks for — carries the choice.
        store.defaults.set("classic", forKey: "style.\(internalDisplay.rawValue)")
        store.defaults.set("card", forKey: "style.\(externalDisplay.rawValue)")
        let preferences = Preferences(defaults: store.defaults)

        preferences.adoptDeclaredStyleFromOverrides(preferring: [internalDisplay, externalDisplay])

        #expect(preferences.declaredStyle == .classic)
        // Adoption never rewrites an override: a display that carries one keeps
        // its style under a user who only upgraded.
        #expect(preferences.style(for: externalDisplay) == .card)

        // A later launch: an existing declaration is never overwritten by a
        // leftover override. `.card` (not the shipped `.notch`) so the assertion
        // cannot be satisfied by an absent key.
        preferences.declaredStyle = .card
        preferences.adoptDeclaredStyleFromOverrides(preferring: [internalDisplay, externalDisplay])

        #expect(preferences.declaredStyle == .card)
    }

    @Test func adoptionWritesNothingWhenNoDisplayCarriesAnOverride() {
        let preferences = Preferences(defaults: store.defaults)

        preferences.adoptDeclaredStyleFromOverrides(preferring: [internalDisplay, externalDisplay])

        // Nothing to preserve ⇒ no key: the shipped default stays a decision
        // the app can still change instead of being frozen in every install.
        #expect(store.defaults.string(forKey: Preferences.declaredStyleKey) == nil)
        #expect(preferences.declaredStyle == .notch)
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

    @Test func hudIndicatorStyleDefaultsToSliderAndPersists() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(preferences.hudIndicatorStyle == .slider)

        preferences.hudIndicatorStyle = .filled

        #expect(Preferences(defaults: store.defaults).hudIndicatorStyle == .filled)
    }

    /// A persisted rawValue of a removed indicator variant — or any garbage —
    /// degrades to the default, never crashes. Writes the raw key directly to
    /// also pin the persistence format.
    @Test func unknownPersistedHUDIndicatorStyleDegradesToSlider() {
        store.defaults.set("neon", forKey: Preferences.hudIndicatorStyleKey)
        #expect(Preferences(defaults: store.defaults).hudIndicatorStyle == .slider)
    }
}
