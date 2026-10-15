import CoreGraphics
import Testing
@testable import Crema

/// The tour's shape, with no window in it: where the steps run, where they stop,
/// what the counter says, what the prominent button offers, and what the real
/// screen does behind each step.
///
/// The one rule with teeth here is the permission's: it may change what the
/// button OFFERS and it may never change where the road goes. A flow that let a
/// missing grant remove the way forward would trap someone who declines on step
/// two inside a window whose whole point is that it can be left — and the trap
/// would be invisible to anyone testing on a Mac where the grant already exists.
struct WelcomeTourFlowTests {

    @Test func theStepsRunInOneOrderAndBothEndsAreTotal() {
        #expect(WelcomeTourStep.allCases == [.welcome, .accessibility, .style, .tryIt, .more, .finish])
        // Total at both ends: asking past either one answers "no such step"
        // instead of wrapping around or trapping.
        #expect(WelcomeTourFlow.previous(before: .welcome) == nil)
        #expect(WelcomeTourFlow.next(after: .finish) == nil)
    }

    /// Kills an off-by-one in either direction: a `next` that skips a step, or a
    /// `previous` that returns the step it was handed, still answers non-nil
    /// everywhere and only shows up when the two are composed.
    @Test func everyStepRoundTripsThroughNextAndBack() {
        for step in WelcomeTourStep.allCases {
            if let forward = WelcomeTourFlow.next(after: step) {
                #expect(WelcomeTourFlow.previous(before: forward) == step, "next then back left \(step)")
            }
            if let backward = WelcomeTourFlow.previous(before: step) {
                #expect(WelcomeTourFlow.next(after: backward) == step, "back then next left \(step)")
            }
        }
        // And the ends are the only ends: exactly one step has nothing after it
        // and exactly one has nothing before it.
        #expect(WelcomeTourStep.allCases.filter { WelcomeTourFlow.next(after: $0) == nil }.count == 1)
        #expect(WelcomeTourStep.allCases.filter { WelcomeTourFlow.previous(before: $0) == nil }.count == 1)
    }

    /// The pairs are written out here rather than derived, so this table and the
    /// production rule are two independent statements of the same fact — a
    /// derivation would agree with any off-by-one the code makes.
    @Test func theProgressCounterIsOneBasedOverEveryStep() {
        let expected: [(step: WelcomeTourStep, index: Int, count: Int)] = [
            (.welcome, 1, 6),
            (.accessibility, 2, 6),
            (.style, 3, 6),
            (.tryIt, 4, 6),
            (.more, 5, 6),
            (.finish, 6, 6),
        ]
        // A step added without a row here fails, instead of being silently uncounted.
        #expect(expected.count == WelcomeTourStep.allCases.count)

        for row in expected {
            let progress = WelcomeTourFlow.progress(row.step)
            #expect(progress.index == row.index, "index of \(row.step)")
            #expect(progress.count == row.count, "count at \(row.step)")
        }
    }

    @Test func theAccessibilityStepOffersTheGrantUntilItIsGrantedAndNeverBlocksTheWay() {
        #expect(WelcomeTourFlow.primaryAction(for: .accessibility, accessibilityGranted: false) == .grantAccess)
        #expect(WelcomeTourFlow.primaryAction(for: .accessibility, accessibilityGranted: true) == .continue)

        // The permission decides the OFFER and nothing else. Everywhere else the
        // answer is identical with and without it, and the only step that ends the
        // tour is the one with nothing after it — so no state of the permission can
        // make a middle step terminal or a terminal step endless.
        for step in WelcomeTourStep.allCases {
            let granted = WelcomeTourFlow.primaryAction(for: step, accessibilityGranted: true)
            let ungranted = WelcomeTourFlow.primaryAction(for: step, accessibilityGranted: false)
            if step != .accessibility {
                #expect(granted == ungranted, "the grant changed the offer on \(step)")
            }
            for action in [granted, ungranted] {
                #expect((action == .done) == (WelcomeTourFlow.next(after: step) == nil), "the end moved at \(step)")
            }
        }
    }

    @Test func theLastStepFinishes() {
        #expect(WelcomeTourFlow.primaryAction(for: .finish, accessibilityGranted: false) == .done)
        #expect(WelcomeTourFlow.primaryAction(for: .finish, accessibilityGranted: true) == .done)
    }

    /// The player is held where the step talks about it and nowhere else: the
    /// key test must find a clear screen for the HUD it asks for, and a player
    /// left up on the last step would outlive the tour by however long the
    /// person reads it.
    @Test func onlyTheWelcomeAndTheStylePickHoldThePlayer() {
        let holding = WelcomeTourStep.allCases.filter(WelcomeTourFlow.holdsThePlayer)
        #expect(holding == [.welcome, .style])
    }

    @Test func onlyTheLastStepPointsAtTheMenuBar() {
        let pointing = WelcomeTourStep.allCases.filter(WelcomeTourFlow.pointsAtTheMenuBar)
        #expect(pointing == [.finish])
    }

    /// The DEBUG flag's vocabulary is the raw values; a renamed case changes the
    /// harness, and this keeps the names the harness documents.
    @Test func theStepsParseFromTheirNames() {
        #expect(WelcomeTourStep(rawValue: "tryIt") == .tryIt)
        #expect(WelcomeTourStep(rawValue: "finish") == .finish)
        #expect(WelcomeTourStep(rawValue: "indicators") == nil)
    }

    /// A Mac with no built-in panel starts with the player off everywhere, so the
    /// tour offers it on the primary display; once any display shows it, nothing
    /// is offered — the tour does not second-guess a display the person chose.
    @Test func thePlayerIsOfferedOnThePrimaryDisplayOnlyWhenNoDisplayShowsIt() {
        let primary = Self.screen("EXT-1")
        let second = Self.screen("EXT-2")

        #expect(WelcomeTourFlow.displayToOfferThePlayer(among: [primary, second]) { _ in false } == primary)
        #expect(WelcomeTourFlow.displayToOfferThePlayer(among: [primary, second]) { $0 == second } == nil)
        #expect(WelcomeTourFlow.displayToOfferThePlayer(among: []) { _ in false } == nil)
    }

    private static func screen(_ uuid: String) -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: uuid),
            name: "LG UltraFine",
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600)),
            isInternal: false
        )
    }
}
