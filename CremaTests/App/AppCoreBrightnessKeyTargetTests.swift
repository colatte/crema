import Testing
@testable import Crema

/// Which display Crema's screen brightness lands on, as the menu bar has to say
/// it. Crema drives the built-in panel by decision, not by accident: a consumed
/// key owes an apply-verify cycle, and a neighbouring app's brightness can be
/// written but never read, so an external display offers no level to step from and
/// nothing to verify against
/// (docs/DECISIONS.md: external-brightness-is-write-only). Correct, documented —
/// and invisible, which is what the menu row closes.
///
/// Pure over the census, the chain reading and the permission — no AppCore
/// instance and no system API, the same reason `styleAuthorityOrder` is static
/// (constructing AppCore boots the real sources, which a unit test may never
/// touch). The census is injected for the same reason DisplayServicesBridge takes
/// a display provider: hardware is not a test fixture.
@MainActor
struct AppCoreBrightnessKeyTargetTests {

    /// The census reading an arrangement produces, as the closure the rule calls.
    /// Built in a local rather than returned inline: a closure body that opens with
    /// a parenthesized labeled list can be parsed as a parameter list.
    private static func arrangement(builtIn: Bool, displays: Int) -> () -> (hasBuiltIn: Bool, count: Int) {
        let reading = (hasBuiltIn: builtIn, count: displays)
        return { reading }
    }

    private static func notice(
        _ chain: MediaKeyChainNotice = .quiet,
        captured: Bool = true,
        builtIn: Bool,
        displays: Int
    ) -> BrightnessKeyTargetNotice {
        AppCore.brightnessKeyTargetNotice(
            chain: chain,
            keysAreCaptured: captured,
            census: arrangement(builtIn: builtIn, displays: displays)
        )
    }

    @Test func aLoneBuiltInPanelHasNothingToDisambiguate() {
        #expect(Self.notice(builtIn: true, displays: 1) == .quiet)
    }

    @Test func aSecondDisplayIsWhatMakesTheTargetWorthNaming() {
        // The field arrangement: the monitor is the main display and the key moves
        // the panel the user is not looking at.
        #expect(Self.notice(builtIn: true, displays: 2) == .builtInAmongOthers)
        #expect(Self.notice(builtIn: true, displays: 3) == .builtInAmongOthers)
    }

    @Test func withNoBuiltInPanelInUseTheLineIsAboutWhatCremaCannotDo() {
        // Clamshell and a Mac that never had a panel answer the same way: the
        // brightness write degrades to false for both, so there is no panel to name.
        #expect(Self.notice(builtIn: false, displays: 1) == .noBuiltInDisplay)
        #expect(Self.notice(builtIn: false, displays: 2) == .noBuiltInDisplay)
    }

    @Test func aNeighbourDrawingTheBarWouldMakeTheSentenceFalse() {
        // Not contention: `.drawingFromBetterDisplay` says the neighbour is
        // REPORTING, whatever its position in the chain, and then the HUD slider
        // writes an external display through its channel. "Crema controls brightness
        // on the built-in display only" would be a lie, not just noise — which is
        // why the gate is the whole of `.quiet` and not the two "ahead" cases.
        #expect(Self.notice(.drawingFromBetterDisplay, builtIn: true, displays: 2) == .quiet)
        #expect(Self.notice(.drawingFromBetterDisplay, builtIn: false, displays: 1) == .quiet)
    }

    @Test func anAppAheadOfUsMayNeverLetTheKeyArrive() {
        // Naming a target under the contention warning printed right above it would
        // contradict that warning.
        for chain: MediaKeyChainNotice in [.anotherAppAhead("Some Other App"), .betterDisplayAheadAndSilent] {
            #expect(Self.notice(chain, builtIn: true, displays: 2) == .quiet)
            #expect(Self.notice(chain, builtIn: false, displays: 1) == .quiet)
        }
    }

    @Test func withoutTheKeyPermissionThereIsNoClaimToMake() {
        // No permission means no tap at all: the warning at the top of the block is
        // the only true thing to say about the keys.
        #expect(Self.notice(captured: false, builtIn: true, displays: 2) == .quiet)
        #expect(Self.notice(captured: false, builtIn: false, displays: 1) == .quiet)
    }

    @Test func aSilencedRowNeverAsksTheSystemWhichDisplaysAreThere() {
        // The gate runs before the census on purpose: a menu that will say nothing
        // costs no display enumeration at all.
        var reads = 0
        let notice = AppCore.brightnessKeyTargetNotice(
            chain: .quiet,
            keysAreCaptured: false,
            census: {
                reads += 1
                return (hasBuiltIn: true, count: 2)
            }
        )

        #expect(notice == .quiet)
        #expect(reads == 0)
    }
}
