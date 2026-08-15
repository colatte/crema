import Foundation
import Testing
@testable import Crema

/// One display's style control, decided before any chrome exists: what the list
/// offers, what it reads back, and what a pick is allowed to write.
///
/// The refusal is pinned HERE and nowhere else on purpose. Measured on macOS
/// 26.5.2 (`scripts/probes/picker-option-disabled.swift`): a SwiftUI `Picker` in
/// `.menu` style DISCARDS `.disabled` on its options — the marked item read back
/// `isEnabled == true` against an `NSPopUpButton` control reading `false` — so no
/// popup can be the thing that stops a pick this screen cannot draw. The chrome
/// dims; this type decides.
struct DisplayStyleOptionsTests {
    /// A panel with no slit: the Mac mini, the external monitor, the clamshell.
    private let notchless = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    /// A notched laptop panel — the only place the notch skin is drawn as picked.
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 590,
        auxRight: 590
    )

    private func options(
        override: String? = nil,
        declared: String? = nil,
        on geometry: ScreenGeometry
    ) -> DisplayStyleOptions {
        DisplayStyleOptions(overrideRawValue: override, declaredRawValue: declared, geometry: geometry)
    }

    @Test func inheritLeadsTheListAndTheStylesFollowInTheirDeclaredOrder() {
        // Kills: inherit appended at the END. Inheriting is not a fourth skin — it
        // is the answer this display gives before it is given one, so the list that
        // opens on a style opens on a choice the display never made.
        let expected: [Style?] = [nil, .notch, .card, .classic]
        #expect(options(on: notched).items.map(\.choice) == expected)
        #expect(options(override: "classic", declared: "card", on: notchless).items.map(\.choice) == expected)
    }

    @Test func inheritIsAlwaysOfferedEvenWhereTheStyleItFallsToIsNotDrawn() {
        // Kills: inherit's enablement derived from the style it would fall to. A
        // display can END UP on a style this panel does not draw, by inheriting a
        // declaration; it can never be PUT there by this row — so returning to the
        // declaration is offered wherever the declaration is.
        let inheritingNotchOnASlitlessPanel = options(declared: "notch", on: notchless)
        #expect(inheritingNotchOnASlitlessPanel.isEnabled(nil))
        #expect(inheritingNotchOnASlitlessPanel.items.first == DisplayStyleOptions.Item(choice: nil, isEnabled: true))
    }

    @Test func aStyleThisScreenCannotDrawIsOfferedDisabled() {
        // Kills: isEnabled == true always — the mutation that offers Notch on a
        // panel with no slit as though picking it would change what is on screen
        // (docs/DECISIONS.md: rendered-style-gates-settings).
        #expect(options(on: notchless).items == [
            DisplayStyleOptions.Item(choice: nil, isEnabled: true),
            DisplayStyleOptions.Item(choice: .notch, isEnabled: false),
            DisplayStyleOptions.Item(choice: .card, isEnabled: true),
            DisplayStyleOptions.Item(choice: .classic, isEnabled: true),
        ])
        // Nothing is withheld from a panel that has the slit. Hoisted out of the
        // macro: #expect's rewrite loses the rethrows inference of
        // allSatisfy(_:) and demands a `try` the call cannot need.
        let everyItemEnabled = options(on: notched).items.allSatisfy(\.isEnabled)
        #expect(everyItemEnabled)
    }

    @Test func pickingInheritClearsTheKeyEvenWhenTheDeclarationNamesTheSameStyle() {
        // Kills: write(nil) → .override(declaration). Inheriting IS the absence of
        // the key: a copy of today's declaration looks identical this afternoon and
        // then shadows the next declaration forever — the bug the declaration exists
        // to fix (docs/DECISIONS.md: global-style-default).
        #expect(options(override: "classic", declared: "card", on: notched).write(for: nil) == .clear)
        // The case where writing the declaration back would be invisible today.
        #expect(options(override: "card", declared: "card", on: notched).write(for: nil) == .clear)
        // And where the declaration is not even drawn here, so an .override of it
        // would persist a style this screen swaps out.
        #expect(options(override: "card", declared: "notch", on: notchless).write(for: nil) == .clear)
    }

    @Test func aPickThisScreenCannotDrawIsRefusedRatherThanWritten() {
        // Kills: write answering .override for every style. This is the guarantee
        // the popup was measured unable to keep — a `.menu` Picker hands its options
        // out enabled whatever `.disabled` says — so the store is protected here.
        let slitless = options(declared: "card", on: notchless)
        #expect(slitless.write(for: .notch) == .refused)
        #expect(slitless.write(for: .card) == .override(.card))
        #expect(slitless.write(for: .classic) == .override(.classic))
        // The same pick where the slit exists is an ordinary override.
        #expect(options(declared: "card", on: notched).write(for: .notch) == .override(.notch))
    }

    @Test func selectionIsThisDisplaysOwnChoiceAndNeverTheDeclaration() {
        // Kills: selection reading the declaration — which would make every display
        // look like it carries a style of its own, so the reset never goes away and
        // the sweep warning above fires over nothing.
        #expect(options(override: "classic", declared: "card", on: notched).selection == .classic)
        #expect(options(declared: "card", on: notched).selection == nil)
        // A rawValue a future version retired is not a choice the user made, so it
        // reads as inherit — the store's own rule, asked instead of re-spelled.
        #expect(options(override: "pill", declared: "card", on: notched).selection == nil)
    }

    @Test func theDeclarationIsTheAllDisplaysValueAndNeverThisDisplaysOverride() {
        // Kills: declaration reading the override — which would make this row's
        // fallback the very value it is supposed to be an alternative to, and the
        // "return to the all-displays style" answer name the style being left.
        #expect(options(override: "classic", declared: "card", on: notched).declaration == .card)
        #expect(options(override: "classic", on: notched).declaration == Preferences.defaultDeclaredStyle)
        // A retired declaration falls to the shipped default: the user's choice is
        // gone and there is nothing under it but the factory answer.
        #expect(options(declared: "pill", on: notched).declaration == Preferences.defaultDeclaredStyle)
    }

    @Test func anOverrideThisScreenCannotDrawIsStillReportedAsSelected() {
        // Kills: selection filtered through isHonoured. Selected AND disabled is a
        // state, not a contradiction — the honest report of "you chose this and this
        // screen does not draw it" (docs/DECISIONS.md: selected-and-disabled-is-a-state).
        // The shape that reaches it: "notch" written while a notched panel was
        // attached, read back on a display that has no slit.
        let legacy = options(override: "notch", declared: "card", on: notchless)
        #expect(legacy.selection == .notch)
        #expect(!legacy.isEnabled(.notch))
        #expect(legacy.items.contains(DisplayStyleOptions.Item(choice: .notch, isEnabled: false)))
    }

    @Test func theNoNotchFootnoteFollowsTheStyleInForceAndNotThePresenceOfAnOverride() {
        // Kills: the footnote gated on the override EXISTING. That gate goes silent
        // on the common case — a display inheriting a Notch declaration it cannot
        // draw, which is the shipped default on notchless hardware — and speaks up
        // where an override already says Card, explaining a fallback that is not
        // happening.
        #expect(options(declared: "notch", on: notchless).footnotes == [.noNotch])
        #expect(options(override: "notch", declared: "card", on: notchless).footnotes == [.noNotch])
        // An override that IS drawn silences it, under a declaration that is not.
        #expect(options(override: "card", declared: "notch", on: notchless).footnotes.isEmpty)
        // And the slit makes the sentence untrue either way.
        #expect(options(declared: "notch", on: notched).footnotes.isEmpty)
        #expect(options(override: "notch", declared: "card", on: notched).footnotes.isEmpty)
    }
}

/// Whether the per-display list is offered at all. The gate is not a count: the
/// question is "is there an answer per display that the all-displays section
/// cannot give?" — and the row is the app's only switch for the now-playing
/// surface, so every attached display has one.
struct DisplayStyleListOfferTests {
    private let store = EphemeralDefaults()

    private func screen(_ id: String, isInternal: Bool) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: id),
            name: isInternal ? "Built-in Retina Display" : "LG UltraFine",
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            isInternal: isInternal
        )
    }

    /// The General footer's deictic sentence ("replaces the per-display styles
    /// BELOW") leans on this: wherever an override exists among the attached
    /// displays, the list that shows it is on screen — an override needs a display
    /// to sit on, and a display is what opens the list, so the sweep can never name
    /// styles nobody can see.
    @Test func anOverrideAnywhereGuaranteesTheListThatShowsIt() {
        let rosters: [[ScreenDescription]] = [
            [screen("A", isInternal: true)],
            [screen("B", isInternal: false)],
            [screen("A", isInternal: true), screen("B", isInternal: false)],
        ]
        for roster in rosters {
            for carrier in roster {
                store.defaults.removeObject(forKey: Preferences.styleKey(for: screen("A", isInternal: true).id))
                store.defaults.removeObject(forKey: Preferences.styleKey(for: screen("B", isInternal: false).id))
                store.defaults.set(Style.classic.rawValue, forKey: Preferences.styleKey(for: carrier.id))
                let exists = PerDisplayStyleOverride.exists(among: roster, in: store.defaults)
                #expect(exists)
                #expect(
                    !exists || DisplayStyleOptions.listIsOffered(for: roster),
                    "an override on \(carrier.id.rawValue) must surface the list in a \(roster.count)-display roster"
                )
            }
        }
    }

    @Test func aSoleBuiltInDisplayOffersTheListBecauseTheSurfaceStartsOnThere() {
        // Kills: the internal panel answered entirely by the all-displays section —
        // the gate this rule shipped with, and the mirror of the bug the external
        // clause below was written for. The style popup on a lone laptop does repeat
        // the declaration, but the row also carries the ONLY "show the player here"
        // switch in the app, and the surface is born ON here — the default is
        // literally `isInternal`, pinned in PreferencesTests — so withholding the row
        // leaves a single-laptop install unable to turn it off.
        #expect(DisplayStyleOptions.listIsOffered(for: [screen("A", isInternal: true)]))
    }

    @Test func aSoleExternalDisplayOffersTheListBecauseNowPlayingStartsOffThere() {
        // Kills: an `isInternal` gate in either direction. The Mac mini class of
        // hardware: the surface is born OFF on a single external panel, and without
        // this row there is no switch anywhere in the app that turns it on.
        #expect(DisplayStyleOptions.listIsOffered(for: [screen("B", isInternal: false)]))
    }

    @Test func twoDisplaysAlwaysOfferTheList() {
        // Kills: the answer narrowed to exactly one display. Two screens are the
        // arrangement where per-display answers can differ from each other at all,
        // and neither of these carries an override to be found.
        let two = [screen("A", isInternal: true), screen("B", isInternal: false)]
        #expect(DisplayStyleOptions.listIsOffered(for: two))
    }

    @Test func aSoleDisplayThatAlreadyCarriesAnOverrideOffersTheListThatClearsIt() {
        // A key written when more displays were attached outlives that arrangement,
        // and this is the promise that it can still be cleared: the row exists for
        // the display, whatever the key says — including a rawValue a future version
        // retired, which reads as inherit and would have opened no list of its own.
        let laptop = screen("A", isInternal: true)
        store.defaults.set("pill", forKey: Preferences.styleKey(for: laptop.id))
        #expect(DisplayStyleOptions.listIsOffered(for: [laptop]))

        store.defaults.set(Style.classic.rawValue, forKey: Preferences.styleKey(for: laptop.id))
        #expect(DisplayStyleOptions.listIsOffered(for: [laptop]))
    }

    @Test func anEmptyRosterOffersNothingAndAsksNothingOfItsFirstElement() {
        // Kills: `displays[0]` in place of the emptiness check. An empty roster is a
        // real state — a Settings window open across a display going away — and a
        // trap there takes the whole test host down, not one section (the run then
        // reports no verdict at all).
        #expect(!DisplayStyleOptions.listIsOffered(for: []))
    }
}
