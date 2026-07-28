import AppKit
import CoreGraphics
import Testing
@testable import Crema

// Test fixtures force-unwrap known values (a nil means the test itself is broken).
// swiftlint:disable force_unwrapping

/// The loop-catcher. These assert the hover behavior at the boundary, not
/// just static geometry: a cursor idling in the hysteresis band (or the resize
/// animation sweeping the frame under it) must not oscillate. A single-threshold
/// detector — the old `.onHover` bound to the animating frame — fails every one.
@MainActor
struct SurfaceHoverModelTests {

    /// A notched 14" display (matches NotchFrameRuleTests): 185 pt slit.
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )

    // MARK: - Pure hysteresis behavior

    /// A cursor parked in the band (inside exit, outside enter) — the exact spot
    /// the animating frame edge used to sweep under — holds whatever state it was
    /// in, across any number of samples. No flip ⇒ no loop.
    @Test func aCursorInTheHysteresisBandNeverOscillates() {
        let regions = SurfaceHoverRegions(
            enter: CGRect(x: 100, y: 100, width: 200, height: 40),
            exit: CGRect(x: 76, y: 76, width: 248, height: 88)
        )
        let model = SurfaceHoverModel(regions: regions)
        let band = CGPoint(x: 200, y: 90)   // below enter (y≥100), inside exit (y≥76)
        #expect(regions.exit.contains(band))
        #expect(!regions.enter.contains(band))

        // Already open: stays open no matter how many samples land on it.
        var inside = true
        for _ in 0..<200 { inside = model.isInside(band, wasInside: inside) }
        #expect(inside)

        // Still closed: a band point does not spuriously open it.
        var closed = false
        for _ in 0..<200 { closed = model.isInside(band, wasInside: closed) }
        #expect(!closed)
    }

    /// Once open, the cursor riding the growing surface's former edge (well inside
    /// the expanded exit region) never flips out — the animation can't collapse it.
    @Test func aCursorRidingTheExpandingEdgeStaysInside() {
        let regions = Style.notch.hoverRegions(on: notched)!
        let model = SurfaceHoverModel(regions: regions)

        // Sit at the compact surface's bottom edge, then let the surface "grow"
        // past: sweep the cursor down through where the expanded region now is,
        // stopping just short of the exit boundary (bounds derived from the
        // regions, not hardcoded, so metric changes don't invalidate the test).
        let compact = regions.enter
        var inside = model.isInside(CGPoint(x: compact.midX, y: compact.minY + 1), wasInside: false)
        #expect(inside)

        var y = compact.minY
        while y > regions.exit.minY + 1 {
            inside = model.isInside(CGPoint(x: compact.midX, y: y), wasInside: inside)
            #expect(inside, "flipped out at y=\(y) — the surface edge moved detection, the loop")
            y -= 4
        }
    }

    /// Simulates the raw flicker sequence a boundary-sitting cursor produced: tiny
    /// jitter across the enter edge, all within exit. Counting transitions proves
    /// there is at most one (the initial open), never an unbounded loop.
    @Test func jitterAcrossTheEnterEdgeProducesNoRepeatedTransitions() {
        let regions = SurfaceHoverRegions(
            enter: CGRect(x: 0, y: 0, width: 100, height: 100),
            exit: CGRect(x: -20, y: -20, width: 140, height: 140)
        )
        let model = SurfaceHoverModel(regions: regions)

        // Jitter around the enter edge (y≈0), all comfortably inside exit.
        let sweep: [CGFloat] = [5, -5, 3, -8, 6, -10, 2, -12, 4, -6]
        var inside = false
        var transitions = 0
        for y in sweep {
            let next = model.isInside(CGPoint(x: 50, y: y), wasInside: inside)
            if next != inside { transitions += 1 }
            inside = next
        }
        #expect(transitions <= 1)
        #expect(inside)   // ended inside (still within exit)
    }

    @Test func entersOnlyInsideTheEnterRegionAndExitsOnlyOutsideTheExitRegion() {
        let regions = SurfaceHoverRegions(
            enter: CGRect(x: 0, y: 0, width: 100, height: 100),
            exit: CGRect(x: -20, y: -20, width: 140, height: 140)
        )
        let model = SurfaceHoverModel(regions: regions)

        #expect(model.isInside(CGPoint(x: 50, y: 50), wasInside: false))      // in enter → opens
        #expect(!model.isInside(CGPoint(x: 110, y: 50), wasInside: false))    // band, closed → stays closed
        #expect(model.isInside(CGPoint(x: 110, y: 50), wasInside: true))      // band, open → stays open
        #expect(!model.isInside(CGPoint(x: 130, y: 50), wasInside: true))     // past exit → closes
    }

    // MARK: - Region contract (detection uses stable geometry, not the frame)

    @Test func notchInitialRegionsHugTheCompactSurfaceWithDirectionalMargins() {
        let style = NotchStyle()
        let track = CoordinatorHarness.playingTrack()
        let regions = Style.notch.hoverRegions(on: notched)!
        let comfort = SurfaceHoverRegions.comfortMargin

        // Seed regions come from the compact frame alone — the union with the
        // expanded frame was the 100 pt stuck band below the compact notch
        // (docs/DECISIONS.md: hover-follows-the-eye).
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        #expect(regions.enter == compact.insetBy(dx: -comfort, dy: -comfort))
        #expect(regions.exit.minX == regions.enter.minX - 8)     // lateral: menu bar pixels
        #expect(regions.exit.maxX == regions.enter.maxX + 8)
        #expect(regions.exit.minY == regions.enter.minY - 16)    // below: app content
        #expect(regions.exit.maxY == regions.enter.maxY)         // top: screen edge, no band
    }

    /// The stuck-hover bug itself, pinned dead: a cursor resting 50 pt below
    /// the visible compact/HUD bottom used to be inside the union-derived exit
    /// (100 pt band) and held the surface forever. With state-derived regions
    /// it is out — the exit reaches at most comfort+bottom past the visible.
    @Test func aCursorRestingBelowTheVisibleSurfaceIsOutside() {
        let style = NotchStyle()
        let hudFrame = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: notched)
        let regions = SurfaceHoverRegions.around(hudFrame, margins: Style.notch.hoverExitMargins)
        let model = SurfaceHoverModel(regions: regions)

        let resting = CGPoint(x: hudFrame.midX, y: hudFrame.minY - 50)
        #expect(!model.isInside(resting, wasInside: true), "50 pt below the visible bottom must release")
        // The intended band still holds: just past the visible edge stays in.
        let justBelow = CGPoint(x: hudFrame.midX, y: hudFrame.minY - 10)
        #expect(model.isInside(justBelow, wasInside: true))
    }

    /// Click and hover truths of one panel never diverge again: the exit band
    /// beyond a state's frame is bounded by comfort+margins on every edge —
    /// never another state's silhouette.
    @Test func exitBandIsBoundedByTheNamedMarginsForEveryStyleAndState() {
        let track = CoordinatorHarness.playingTrack()
        let states: [PresentationState] = [
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        let comfort = SurfaceHoverRegions.comfortMargin
        for style in Style.allCases {
            let margins = style.hoverExitMargins
            for state in states {
                let frame = style.frame(for: state, on: notched)
                guard !frame.isEmpty else { continue }
                let regions = SurfaceHoverRegions.around(frame, margins: margins)
                #expect(regions.exit.minX == frame.minX - comfort - margins.lateral, "\(style) \(state)")
                #expect(regions.exit.maxX == frame.maxX + comfort + margins.lateral, "\(style) \(state)")
                #expect(regions.exit.minY == frame.minY - comfort - margins.bottom, "\(style) \(state)")
                #expect(regions.exit.maxY == frame.maxY + comfort + margins.top, "\(style) \(state)")
            }
        }
    }

    /// The monitor sees moves and mouse-ups — the ups re-sync after a drag,
    /// closing the unbounded drag-exit — but deliberately NOT drags: a live
    /// drag on the surface's own control overshoots the edge (the slider
    /// clamps while the cursor travels), and sampling it would release the
    /// hover hold mid-gesture (docs/DECISIONS.md: hover-follows-the-eye).
    @Test func monitorSamplesMovesAndUpsButNeverDrags() {
        let mask = SurfaceHoverMonitor.sampleEventMask
        for required: NSEvent.EventTypeMask in [.mouseMoved, .leftMouseUp, .rightMouseUp, .otherMouseUp] {
            #expect(mask.contains(required))
        }
        for excluded: NSEvent.EventTypeMask in [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged] {
            #expect(!mask.contains(excluded))
        }
    }

    /// Every band on an edge that can move during the open spring must absorb
    /// its overshoot, or the sweeping edge re-creates the flicker the regions
    /// exist to kill. The exemption is per-anchor, not app-wide: notch/card
    /// are top-anchored (and the notch's top is the screen edge), but the
    /// bottom-anchored classic grows UPWARD — its top band must absorb too.
    @Test func stickyBandsAbsorbTheOpenSpringOvershoot() {
        let comfort = SurfaceHoverRegions.comfortMargin
        for style in Style.allCases {
            let margins = style.hoverExitMargins
            #expect(comfort + margins.lateral >= SurfaceAnimation.overshootHeadroom, "\(style) lateral")
            #expect(comfort + margins.bottom >= SurfaceAnimation.overshootHeadroom, "\(style) bottom")
            if style.surfaceVerticalAnchor != .top {
                #expect(comfort + margins.top >= SurfaceAnimation.overshootHeadroom, "\(style) top (moving edge)")
            }
        }
    }

    /// The apply-time retarget errs tight (rule frame ∩ last rendered): the
    /// previous state's silhouette never survives a state change, and the rule
    /// ceiling never overrides a narrower rendered truth — each stale rect
    /// alone re-created a closed bug (the notch stuck band; the card's dead
    /// air).
    @Test func applyTimeRegionsErrTightBetweenRuleAndRendered() {
        let margins = SurfaceHoverRegions.Margins.uniform
        let compact = CGRect(x: 0, y: 900, width: 185, height: 76)
        let expanded = CGRect(x: 0, y: 824, width: 185, height: 152)
        #expect(
            SurfaceHoverRegions.forApply(ruleFrame: compact, lastRendered: expanded, margins: margins)
                == .around(compact, margins: margins)
        )
        let ceiling = CGRect(x: 0, y: 0, width: 280, height: 64)
        let hugged = CGRect(x: 50, y: 0, width: 180, height: 64)
        #expect(
            SurfaceHoverRegions.forApply(ruleFrame: ceiling, lastRendered: hugged, margins: margins)
                == .around(hugged, margins: margins)
        )
        #expect(
            SurfaceHoverRegions.forApply(ruleFrame: compact, lastRendered: nil, margins: margins)
                == .around(compact, margins: margins)
        )
    }

    @Test func exitContainsEnterSoTheBandIsAlwaysSticky() {
        for style in [Style.notch, .card] {
            let regions = style.hoverRegions(on: notched)!
            #expect(regions.exit.contains(regions.enter), "\(style): exit must contain enter")
        }
    }

    @Test func cardSeedRegionsComeFromItsCompactFramePlusComfort() {
        let track = CoordinatorHarness.playingTrack()
        let regions = Style.card.hoverRegions(on: notched)!
        let comfort = SurfaceHoverRegions.comfortMargin
        let compact = CardStyle().frame(for: .nowPlaying(track, expanded: false), on: notched)
        #expect(regions.enter == compact.insetBy(dx: -comfort, dy: -comfort))
    }

    @Test func everyStyleExposesHoverRegions() {
        for style in Style.allCases {
            let regions = style.hoverRegions(on: notched)
            #expect(regions != nil, "\(style)")
            if let regions {
                #expect(regions.exit.contains(regions.enter), "\(style): exit must contain enter")
            }
        }
    }

    @Test func hoverCommitIsDebouncedForTheNotchAndImmediateOtherwise() {
        #expect(Style.notch.hoverCommit == .debounced)
        #expect(Style.card.hoverCommit == .immediate)
        #expect(Style.classic.hoverCommit == .immediate)
    }

    // MARK: - Adaptive card: region tracks the rendered surface, not the ceiling

    /// A plain (notch-less) display — the card's home.
    private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))

    /// The visible surface a rendered `size` draws as: top-center anchored in
    /// the fixed window, exactly like the click region (SurfaceClickThrough).
    private func cardVisibleRect(_ size: CGSize) -> CGRect {
        SurfaceClickThrough.surfaceRect(
            size: size,
            window: CardStyle().windowFrame(on: plain),
            anchor: Style.card.surfaceVerticalAnchor
        )
    }

    /// Margin dispatch: the notch is directional (lateral tight against the
    /// menu bar, no top band at the screen edge); floating styles uniform.
    @Test func exitMarginsAreDirectionalOnTheNotchAndUniformElsewhere() {
        let notchMargins = Style.notch.hoverExitMargins
        #expect(notchMargins == SurfaceHoverRegions.Margins(top: 0, lateral: 8, bottom: 16))
        #expect(Style.card.hoverExitMargins == .uniform)
        #expect(Style.classic.hoverExitMargins == .uniform)
    }

    /// The pin: for each layoutKind, the input region is the visible frame plus
    /// exactly the named comfort margin (enter) and the sticky band on top of it
    /// (exit) — derived from the rendered size, not the rule ceiling.
    @Test func cardRegionsAreTheVisibleFramePlusTheNamedMargins() {
        let comfort = SurfaceHoverRegions.comfortMargin
        let band = SurfaceHoverRegions.Margins.uniform
        let renderedSizes: [CGSize] = [
            CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height),   // compact, hugged to floor
            CGSize(width: CardMetrics.expandedMinWidth, height: CardMetrics.expanded.height),  // expanded, hugged to floor
            CardMetrics.hudSystemSize, // HUD, fixed rule size
        ]
        for size in renderedSizes {
            let visible = cardVisibleRect(size)
            let regions = SurfaceHoverRegions.around(visible)
            #expect(regions.enter == visible.insetBy(dx: -comfort, dy: -comfort))
            #expect(regions.exit == visible.insetBy(dx: -(comfort + band.lateral), dy: -(comfort + band.bottom)))
            #expect(regions.exit.contains(regions.enter), "exit must stay sticky over enter")
        }
    }

    /// The bug itself: a hugged compact card (180 wide) inside the 280-wide rule
    /// ceiling leaves 50 pt of dead air per side. A point in that dead air is
    /// inside the old rule-derived enter but outside the rendered-surface enter —
    /// so hover no longer arms before the cursor reaches the visible edge.
    @Test func cardEnterExcludesTheDeadAirBesideAHuggedCard() {
        let hugged = CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height)
        let visible = cardVisibleRect(hugged)
        let tracked = SurfaceHoverRegions.around(visible)

        // The former, rule-derived region (compact rule ceiling + comfort).
        let ruleEnter = Style.card.hoverRegions(on: plain)!.enter
        #expect(ruleEnter.width == CardMetrics.compact.width + 2 * SurfaceHoverRegions.comfortMargin)

        // A point 120 pt right of center: inside the 280-wide ceiling (±140),
        // beyond the 96 pt visible+comfort half (180/2 + 6) — the exact dead air.
        let deadAir = CGPoint(x: visible.midX + 120, y: visible.midY)
        #expect(ruleEnter.contains(deadAir), "the ceiling used to arm here")
        #expect(!tracked.enter.contains(deadAir), "the rendered region must not")
        // The visible edge itself still arms (comfort margin included).
        #expect(tracked.enter.contains(CGPoint(x: visible.maxX, y: visible.midY)))
    }

    /// compact→expanded retargets: the region for the wider/taller expanded
    /// surface contains the compact one, so a cursor that opened the card stays
    /// inside across the transition (no open/close loop at the seam).
    @Test func expandedRegionContainsTheCompactRegionAcrossTheTransition() {
        let compact = SurfaceHoverRegions.around(
            cardVisibleRect(CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height))
        )
        let expanded = SurfaceHoverRegions.around(
            cardVisibleRect(CGSize(width: CardMetrics.expandedMinWidth, height: CardMetrics.expanded.height))
        )
        // The expanded exit swallows the compact enter: whatever opened the card
        // is still held once it grows.
        #expect(expanded.exit.contains(compact.enter))
    }
}

// swiftlint:enable force_unwrapping
