import AppKit
import Testing
@testable import Crema

/// The real panel, instantiated.
///
/// Everything above it (reconciliation, frame math, style resolution) is well
/// pinned, and everything this class *binds* is invisible from there: two
/// mutations, one handing SwiftUI the power to size the window and one dropping
/// the fixed frame altogether, both leave every other test green (measured
/// across 729 tests). Those are the same two invariants
/// AGENTS.md names in "Never do" as the cure for a whole family of
/// intermittent blinks, so they get a witness here.
@MainActor
struct NSPanelPresentationPanelTests {

    private func screen() -> ScreenDescription {
        ScreenDescription(
            id: DisplayUUID(rawValue: "PANEL-TEST"),
            name: "Built-in Retina Display",
            geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982)),
            isInternal: true
        )
    }

    private func panel(_ style: Style = .card) -> (NSPanelPresentationPanel, ScreenDescription, CoordinatorHarness) {
        panel(surface: .skin(style))
    }

    private func panel(surface: PanelSurface) -> (NSPanelPresentationPanel, ScreenDescription, CoordinatorHarness) {
        let harness = CoordinatorHarness()
        let screen = screen()
        return (
            NSPanelPresentationPanel(
                screen: screen, surface: surface, coordinator: harness.coordinator, lowPower: nil
            ),
            screen, harness
        )
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

    @Test func aSplitCardPanelDrawsItsOwnLayerInItsOwnWindow() {
        // Built from its surface: the HUD's panel reads the HUD alone, runs the bar
        // the way its placement does, and sits in a window around that spot — the
        // card's view in the card's window would be clipped there, and a flat bar
        // would lie across an upright surface.
        let (hudPanel, screen, _) = panel(surface: .cardHUD(.middleLeft))
        #expect(hudPanel.drawnLayers == .hud)
        #expect(hudPanel.hudAxis == .vertical)
        #expect(hudPanel.currentWindowFrame == PanelSurface.cardHUD(.middleLeft).windowFrame(on: screen.geometry))

        let (cardPanel, _, _) = panel(surface: .cardNowPlaying)
        #expect(cardPanel.drawnLayers == .nowPlaying)
        #expect(cardPanel.hudAxis == .horizontal)
        #expect(cardPanel.currentWindowFrame == Style.card.windowFrame(on: screen.geometry))

        let (shared, _, _) = panel(.card)
        #expect(shared.drawnLayers == .both)
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
        // The region math is pinned in SurfaceHoverModelTests; what is invisible
        // there is whether the panel PUSHES it. A mutation dropping the retarget
        // leaves every other test green while the previous state's silhouette stays live —
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

    @Test func aSizeReportRetargetsHoverToTheRenderedSurface() {
        // The other push the regions depend on: the apply's retarget errs tight on
        // a report that predates the state, so a surface growing into its new state
        // is under-armed until the view reports what it drew. Without the report's
        // retarget the band stays at the apply's guess, short of the pixels the
        // pointer is over (docs/DECISIONS.md: hover-follows-the-eye).
        let (panel, screen, harness) = self.panel()
        let track = CoordinatorHarness.playingTrack()
        let compact = Style.card.frame(for: .nowPlaying(track, expanded: false), on: screen.geometry)
        let expanded = Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry)
        apply(panel, compact)
        panel.surfaceSizeChanged(compact.size)
        apply(panel, expanded)

        let rendered = SurfaceClickThrough.surfaceRect(
            size: expanded.size,
            window: Style.card.windowFrame(on: screen.geometry),
            anchor: Style.card.surfaceVerticalAnchor
        )
        let widened = SurfaceHoverRegions.around(rendered, margins: Style.card.hoverExitMargins)
        #expect(panel.currentHoverRegions != widened, "the apply alone reached the rendered surface")

        panel.surfaceSizeChanged(expanded.size)
        #expect(panel.currentHoverRegions == widened)

        withExtendedLifetime(harness) {}
    }

    @Test func theClickRegionComesFromTheRenderedSurfaceNotTheRuleFrame() {
        // The hosting view reports its size during CONSTRUCTION, so the reported
        // rect already owns the click region at the very first apply; a rect equal
        // to the rule frame would mean the surface never reported.
        //
        // Asserting the rect differs from the rule frame is what says "reported
        // path". If a change ever makes the rule frame win, this fails.
        let (panel, screen, harness) = self.panel()
        let track = CoordinatorHarness.playingTrack()
        let expanded = Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry)

        apply(panel, expanded)

        #expect(panel.currentInteractiveRect != .zero, "no region at all means clicks fall through the surface")
        #expect(panel.currentInteractiveRect != expanded, "the rule frame won, so the surface never reported")
        #expect(expanded.contains(panel.currentInteractiveRect), "the drawn surface lives inside its state's rule frame")

        withExtendedLifetime(harness) {}
    }

    @Test func anApplyOverAStaleSilhouetteClampsClicksToTheStatesRuleFrame() {
        // The trace this pins: expanded card visible → hidden freezes the
        // silhouette (the view keeps reporting the last-visible size) → a HUD
        // keypress applies a much smaller frame. The apply-time refresh derives
        // the click region from that FROZEN report, and before the clamp it
        // captured clicks ~90 pt taller and ~70 pt wider than the drawn HUD,
        // over the apps below, until the first fresh report. The rule is the
        // hover retarget's: err tight, silhouette ∩ the state's rule frame.
        let (panel, screen, harness) = self.panel()
        let track = CoordinatorHarness.playingTrack()
        let expanded = Style.card.frame(for: .nowPlaying(track, expanded: true), on: screen.geometry)

        apply(panel, expanded)
        // A fresh report at the expanded size — the silhouette that freezes.
        panel.surfaceSizeChanged(expanded.size)
        apply(panel, Style.card.frame(for: .hidden, on: screen.geometry))
        #expect(panel.currentInteractiveRect == .zero, "a hidden ghost must never capture clicks")

        let hud = Style.card.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: screen.geometry)
        apply(panel, hud)
        #expect(!panel.currentInteractiveRect.isEmpty, "a consumed key still owes a clickable surface")
        #expect(
            hud.contains(panel.currentInteractiveRect),
            "the stale silhouette leaked past the state's tight frame"
        )

        // A fresh report then retargets to the rendered truth, unclamped —
        // click keeps following the surface as drawn (hover-follows-the-eye).
        panel.surfaceSizeChanged(hud.size)
        let rendered = SurfaceClickThrough.surfaceRect(
            size: hud.size,
            window: Style.card.windowFrame(on: screen.geometry),
            anchor: Style.card.surfaceVerticalAnchor
        )
        #expect(panel.currentInteractiveRect == rendered)

        withExtendedLifetime(harness) {}
    }

    @Test func theStaleReportClickRuleIsTheIntersectionNormalizedToZero() {
        // The pure half of the clamp above: intersection where the rects
        // agree, .zero (never CGRect.null) when they do not.
        let rule = CGRect(x: 100, y: 100, width: 210, height: 42)
        let stale = CGRect(x: 65, y: 30, width: 280, height: 154)
        #expect(
            NSPanelPresentationPanel.staleReportClickRect(rendered: stale, ruleFrame: rule)
                == CGRect(x: 100, y: 100, width: 210, height: 42)
        )
        let disjoint = CGRect(x: 900, y: 900, width: 10, height: 10)
        #expect(NSPanelPresentationPanel.staleReportClickRect(rendered: disjoint, ruleFrame: rule) == .zero)
        #expect(NSPanelPresentationPanel.staleReportClickRect(rendered: stale, ruleFrame: .zero) == .zero)
    }

    @Test func theFixedWindowIsTheStylesOwnMaximum() {
        // It is the style's rule that decides, not the panel: a window smaller
        // than the largest state would crop the surface it is supposed to hold.
        let (panel, screen, harness) = self.panel()
        #expect(panel.currentWindowFrame == Style.card.windowFrame(on: screen.geometry))
        withExtendedLifetime(harness) {}
    }
}
