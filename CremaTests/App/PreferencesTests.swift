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

    /// Two readers of one key: this type, and the menu bar's @AppStorage, which
    /// cannot call an instance getter. The shared resolver is what keeps them from
    /// disagreeing about the shipped default or about a rawValue a future version
    /// retires — a second literal on the menu side would start lying the day the
    /// default changes.
    @Test func theMenuAndThePreferenceResolveTheDeclaredStyleTheSameWay() {
        let preferences = Preferences(defaults: store.defaults)

        // Unset: both sides land on the same shipped default.
        #expect(Preferences.declaredStyle(fromRawValue: nil) == preferences.declaredStyle)
        #expect(Preferences.declaredStyle(fromRawValue: nil) == Preferences.defaultDeclaredStyle)
        // A style removed since ("pill", "circular") is no declaration at all.
        #expect(Preferences.declaredStyle(fromRawValue: "pill") == Preferences.defaultDeclaredStyle)

        // And a real declaration reads back identically from the raw value the
        // menu's @AppStorage sees.
        preferences.declaredStyle = .classic
        let raw = store.defaults.string(forKey: Preferences.declaredStyleKey)
        #expect(Preferences.declaredStyle(fromRawValue: raw) == .classic)
        #expect(preferences.declaredStyle == .classic)
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

    /// The per-display control has to tell "inherits" from "has its own", and it
    /// asks the same question resolution answers. The table is written
    /// independently of the production rule on purpose: what bites is the VALUE
    /// each combination lands on, not that some accessor answered.
    @Test func theOverrideAccessorAgreesWithTheResolverIncludingTheRetiredRawValue() {
        let preferences = Preferences(defaults: store.defaults)
        // (override rawValue, declaration rawValue) → (what the display draws,
        // what the control shows as this display's own).
        struct Combination {
            let override: String?
            let declared: String?
            let resolved: Style
            let own: Style?
        }
        let cases: [Combination] = [
            Combination(override: "card", declared: "classic", resolved: .card, own: .card),
            Combination(override: "card", declared: nil, resolved: .card, own: .card),
            // A rawValue a future version retired is no choice the user made, so
            // it is no override: it falls through to the DECLARATION, and where
            // there is none, to the shipped default.
            Combination(override: "pill", declared: "classic", resolved: .classic, own: nil),
            Combination(override: "pill", declared: nil, resolved: Preferences.defaultDeclaredStyle, own: nil),
            Combination(override: nil, declared: "classic", resolved: .classic, own: nil),
            Combination(override: nil, declared: nil, resolved: Preferences.defaultDeclaredStyle, own: nil),
        ]

        for testCase in cases {
            let label = "override \(testCase.override ?? "unset") under declaration \(testCase.declared ?? "unset")"
            store.defaults.removeObject(forKey: Preferences.styleKey(for: internalDisplay))
            store.defaults.removeObject(forKey: Preferences.declaredStyleKey)
            if let override = testCase.override {
                store.defaults.set(override, forKey: Preferences.styleKey(for: internalDisplay))
            }
            if let declared = testCase.declared {
                store.defaults.set(declared, forKey: Preferences.declaredStyleKey)
            }

            #expect(preferences.style(for: internalDisplay) == testCase.resolved, "\(label)")
            #expect(preferences.styleOverride(for: internalDisplay) == testCase.own, "\(label)")
            // The shared resolver is the same rule, so a per-display picker
            // reading raw values through @AppStorage cannot disagree with the
            // app about what any of these combinations means.
            #expect(
                Preferences.style(overrideRawValue: testCase.override, declaredRawValue: testCase.declared) == testCase.resolved,
                "\(label)"
            )
        }
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

    /// Returning ONE display to the declaration is not the all-displays sweep:
    /// the neighbour that carries its own choice keeps it, and the declaration
    /// itself is untouched. "Inherits" is the ABSENCE of the key — writing the
    /// declaration into it would freeze today's declaration and shadow the next
    /// one, which is the bug the declaration exists to fix.
    @Test func clearingOneDisplaysStyleReturnsItToTheDeclarationAndSparesTheOthers() {
        let preferences = Preferences(defaults: store.defaults)
        preferences.declaredStyle = .classic
        preferences.setStyle(.card, for: internalDisplay)
        preferences.setStyle(.notch, for: externalDisplay)
        preferences.setShowsNowPlaying(false, on: internalDisplay)

        preferences.clearStyle(for: internalDisplay)

        #expect(preferences.styleOverride(for: internalDisplay) == nil)
        #expect(preferences.style(for: internalDisplay) == .classic)
        // Removal, not a copy of the declaration: a later declaration has to
        // reach this display, which only an absent key allows.
        preferences.declaredStyle = .card
        #expect(preferences.style(for: internalDisplay) == .card)

        // The neighbour, the declaration and the unrelated per-display key all
        // survive one display's clear.
        #expect(preferences.styleOverride(for: externalDisplay) == .notch)
        #expect(preferences.declaredStyle == .card)
        #expect(!preferences.showsNowPlaying(on: internalDisplay, isInternal: true))
        // The key a per-display picker binds @AppStorage to is the one this
        // type writes and clears — a second spelling would bind the picker to a
        // key nothing reads.
        #expect(store.defaults.string(forKey: Preferences.styleKey(for: externalDisplay)) == Style.notch.rawValue)
        #expect(store.defaults.object(forKey: Preferences.styleKey(for: internalDisplay)) == nil)
        // Persisted, not just in this instance's view of the store.
        #expect(Preferences(defaults: store.defaults).style(for: internalDisplay) == .card)
    }

    /// Clearing a display that inherits is a no-op on the store: it must not
    /// materialize the key (a written key is an override, and the display would
    /// stop following the declaration) and must not touch the declaration —
    /// "return this display to the declaration" is not "declare anything".
    @Test func clearingADisplayWithNoOverrideWritesNothing() {
        let preferences = Preferences(defaults: store.defaults)

        preferences.clearStyle(for: externalDisplay)

        // The whole suite, so any key at all counts as a write.
        let written = store.defaults.persistentDomain(forName: store.suiteName) ?? [:]
        #expect(written.isEmpty, "clearing an inherited display wrote \(written.keys.sorted())")
        #expect(store.defaults.object(forKey: Preferences.styleKey(for: externalDisplay)) == nil)
        #expect(store.defaults.string(forKey: Preferences.declaredStyleKey) == nil)
        #expect(preferences.styleOverride(for: externalDisplay) == nil)
        #expect(preferences.style(for: externalDisplay) == Preferences.defaultDeclaredStyle)
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

    /// Two readers of the unset value: this type, and a per-display control that
    /// binds the raw key through @AppStorage and cannot call an instance
    /// accessor. Naming the default once is what keeps the control from showing
    /// "off" on the internal display the moment the default changes.
    @Test func theShowNowPlayingDefaultIsNamedOnceAndBothReadersAgree() {
        let preferences = Preferences(defaults: store.defaults)

        #expect(Preferences.defaultShowsNowPlaying(isInternal: true))
        #expect(!Preferences.defaultShowsNowPlaying(isInternal: false))
        #expect(
            preferences.showsNowPlaying(on: internalDisplay, isInternal: true)
                == Preferences.defaultShowsNowPlaying(isInternal: true)
        )
        #expect(
            preferences.showsNowPlaying(on: externalDisplay, isInternal: false)
                == Preferences.defaultShowsNowPlaying(isInternal: false)
        )

        // A written value beats the default on both sides, so the agreement
        // above is about the UNSET reading and nothing else — and the key the
        // control binds is the one this type writes.
        preferences.setShowsNowPlaying(true, on: externalDisplay)

        #expect(preferences.showsNowPlaying(on: externalDisplay, isInternal: false))
        #expect(store.defaults.object(forKey: Preferences.showsNowPlayingKey(for: externalDisplay)) as? Bool == true)
    }

    @Test func nativeOSDSuppressionDefaultsToOffAndPersists() {
        // Suppression is opt-in — the user activates it.
        let preferences = Preferences(defaults: store.defaults)
        #expect(!preferences.suppressesNativeOSD)

        preferences.suppressesNativeOSD = true

        #expect(Preferences(defaults: store.defaults).suppressesNativeOSD)
    }

    /// The tour's once-per-install flag. Off by default, so an install that has
    /// never recorded anything is a first launch — the reading a missing key has
    /// to give, since it is the only one a fresh install can produce.
    @Test func welcomeTourFlagDefaultsToFalseAndPersists() {
        let preferences = Preferences(defaults: store.defaults)
        #expect(!preferences.hasSeenWelcomeTour)

        preferences.hasSeenWelcomeTour = true

        #expect(Preferences(defaults: store.defaults).hasSeenWelcomeTour)
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
