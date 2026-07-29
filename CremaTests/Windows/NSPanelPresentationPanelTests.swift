import AppKit
import Testing
@testable import Crema

/// The real panel, instantiated — which until now nothing in the suite did.
///
/// Everything above it (reconciliation, frame math, style resolution) is well
/// pinned, and everything this class *binds* was invisible: two mutations, one
/// handing SwiftUI the power to size the window and one dropping the fixed frame
/// altogether, both left all 729 tests green. Those are the same two invariants
/// CLAUDE.md names in "Nunca fazer" and design-reference §1.3 calls the cure for
/// a whole family of intermittent blinks, so they get a witness here.
@MainActor
struct NSPanelPresentationPanelTests {

    private func screen() -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: "PANEL-TEST"),
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            isInternal: true
        )
    }

    private func panel(_ style: Style = .card) -> (NSPanelPresentationPanel, ScreenDescription, CoordinatorHarness) {
        let harness = CoordinatorHarness()
        let screen = screen()
        return (NSPanelPresentationPanel(screen: screen, style: style, coordinator: harness.coordinator), screen, harness)
    }

    private func apply(_ panel: NSPanelPresentationPanel, _ frame: CGRect) {
        panel.apply(
            frame: frame,
            hoverArmed: !frame.isEmpty,
            showsNowPlaying: true,
            showsHUD: true,
            showsControls: true,
            hudIndicatorStyle: .slider,
            invokeZone: nil
        )
    }

    @Test func swiftUINeverGetsToSizeTheWindow() {
        // `.standardBounds` (the default) installs constraints that let the view
        // resize the panel from its own layout — the window-vs-render race.
        for style in [Style.card, .classic, .notch] {
            let (panel, _, harness) = self.panel(style)
            #expect(panel.contentIsBarredFromSizingTheWindow)
            withExtendedLifetime(harness) {}
        }
    }

    @Test func theWindowIsPlacedOnceAndNeverMovesWithTheState() {
        // The whole fixed-window model in one assertion: the surface animates
        // inside a window that was decided at construction. If a state ever
        // reached `setFrame` again, this is where it would show.
        let (panel, screen, harness) = self.panel()
        let atBirth = panel.currentWindowFrame
        #expect(!atBirth.isEmpty)

        let hud = SystemHUD(kind: .volume, value: 0.5)
        apply(panel, Style.card.frame(for: .hud(hud), on: screen.geometry))
        #expect(panel.currentWindowFrame == atBirth)

        let track = CoordinatorHarness.playingTrack()
        apply(panel, Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry))
        #expect(panel.currentWindowFrame == atBirth)

        apply(panel, Style.card.frame(for: .hidden, on: screen.geometry))
        #expect(panel.currentWindowFrame == atBirth)

        withExtendedLifetime(harness) {}
    }

    @Test func everyApplyRetargetsHoverAtTheStateItJustDrew() {
        // The region math is pinned in SurfaceHoverModelTests; what was invisible
        // is whether the panel PUSHES it. A mutation dropping the retarget left
        // the suite green while the previous state's silhouette stayed live —
        // an invisible band that keeps holding the surface open where nothing is
        // drawn any more (docs/DECISIONS.md: hover-follows-the-eye).
        let (panel, screen, harness) = self.panel()
        let track = CoordinatorHarness.playingTrack()
        #expect(panel.currentHoverRegions != nil)
        let atBirth = panel.hoverRetargetRequests

        apply(panel, Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry))
        #expect(panel.hoverRetargetRequests == atBirth + 1)

        apply(panel, Style.card.frame(for: .nowPlaying(track, expanded: false), on: screen.geometry))
        #expect(panel.hoverRetargetRequests == atBirth + 2)

        // Hidden deliberately leaves the region alone: hover is disarmed there,
        // and the next apply retargets before arming again.
        apply(panel, Style.card.frame(for: .hidden, on: screen.geometry))
        #expect(panel.hoverRetargetRequests == atBirth + 2)

        withExtendedLifetime(harness) {}
    }

    @Test func theClickRegionComesFromTheRenderedSurfaceNotTheRuleFrame() {
        // This is the measurement that retired a whole settle mechanism. The rule
        // frame was documented as the fallback for skins that do not report their
        // size, with a union-then-tighten shrink path behind it and a calibrated
        // constant to time it. But the hosting view reports during CONSTRUCTION, so
        // the reported path already owns the rect when the very first apply lands —
        // the fallback could not run, its constant was asserted only against another
        // constant, and anyone calibrating click-during-close was turning a dial
        // wired to nothing.
        //
        // Asserting the rect differs from the rule frame is what says "reported
        // path". If a change ever makes the rule frame win, this fails and the
        // deleted machinery is back on the table.
        let (panel, screen, harness) = self.panel()
        let track = CoordinatorHarness.playingTrack()
        let expanded = Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry)

        apply(panel, expanded)

        #expect(panel.currentInteractiveRect != .zero, "no region at all means clicks fall through the surface")
        #expect(panel.currentInteractiveRect != expanded, "the rule frame won, so the surface never reported")
        #expect(expanded.contains(panel.currentInteractiveRect), "the drawn surface lives inside its state's rule frame")

        withExtendedLifetime(harness) {}
    }

    @Test func theFixedWindowIsTheStylesOwnMaximum() {
        // It is the style's rule that decides, not the panel: a window smaller
        // than the largest state would crop the surface it is supposed to hold.
        let (panel, screen, harness) = self.panel()
        #expect(panel.currentWindowFrame == Style.card.windowFrame(on: screen.geometry))
        withExtendedLifetime(harness) {}
    }
}
