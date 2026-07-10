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

    @Test func notchRegionsAreTheCompactAndExpandedFramesNotTheAnimatingOne() {
        let style = NotchStyle()
        let track = CoordinatorHarness.playingTrack()
        let regions = Style.notch.hoverRegions(on: notched)!

        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: notched)
        #expect(regions.enter == compact)
        #expect(regions.exit == expanded.insetBy(dx: -SurfaceHoverRegions.defaultExitMargin, dy: -SurfaceHoverRegions.defaultExitMargin))
    }

    @Test func exitContainsEnterSoTheBandIsAlwaysSticky() {
        for style in [Style.notch, .card] {
            let regions = style.hoverRegions(on: notched)!
            #expect(regions.exit.contains(regions.enter), "\(style): exit must contain enter")
        }
    }

    @Test func cardRegionsComeFromItsCompactAndExpandedFrames() {
        let track = CoordinatorHarness.playingTrack()
        let regions = Style.card.hoverRegions(on: notched)!
        #expect(regions.enter == CardStyle().frame(for: .nowPlaying(track, expanded: false), on: notched))
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

    /// Only the width-hugging card retargets to the rendered surface; the
    /// fixed-width styles' rendered size equals their rule frame, so they keep
    /// the static rule regions (and must, to stay behaviorally unchanged).
    @Test func onlyTheCardTracksTheRenderedSurface() {
        #expect(Style.card.hoverTracksRenderedSurface)
        #expect(!Style.notch.hoverTracksRenderedSurface)
        #expect(!Style.classic.hoverTracksRenderedSurface)
    }

    /// The pin: for each layoutKind, the input region is the visible frame plus
    /// exactly the named comfort margin (enter) and the sticky band on top of it
    /// (exit) — derived from the rendered size, not the rule ceiling.
    @Test func cardRegionsAreTheVisibleFramePlusTheNamedMargins() {
        let comfort = SurfaceHoverRegions.comfortMargin
        let band = SurfaceHoverRegions.defaultExitMargin
        let renderedSizes: [CGSize] = [
            CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height),   // compact, hugged to floor
            CGSize(width: CardMetrics.expandedMinWidth, height: CardMetrics.expanded.height),  // expanded, hugged to floor
            CardMetrics.hudSystemSize, // HUD, fixed rule size
        ]
        for size in renderedSizes {
            let visible = cardVisibleRect(size)
            let regions = SurfaceHoverRegions.around(visible)
            #expect(regions.enter == visible.insetBy(dx: -comfort, dy: -comfort))
            #expect(regions.exit == visible.insetBy(dx: -(comfort + band), dy: -(comfort + band)))
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

        // The former, rule-derived region (compact rule frame = the ceiling).
        let ruleEnter = Style.card.hoverRegions(on: plain)!.enter
        #expect(ruleEnter.width == CardMetrics.compact.width)   // 280 ceiling, not 180

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

    // MARK: - Regression: fixed-width styles' rule regions are unchanged

    /// Notch/Classic keep the exact static rule-derived regions (enter = compact
    /// rule frame, no comfort margin) — the fix routes only the adaptive card
    /// through the rendered path, so these must read byte-for-byte as before.
    @Test func fixedWidthStyleRegionsStayRuleDerived() {
        let track = CoordinatorHarness.playingTrack()
        for style in [Style.notch, .classic] {
            guard let regions = style.hoverRegions(on: notched) else {
                Issue.record("\(style) has no regions")
                continue
            }
            let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
            let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: notched)
            #expect(regions.enter == compact, "\(style): enter is the bare compact rule frame")
            #expect(
                regions.exit == compact.union(expanded)
                    .insetBy(dx: -SurfaceHoverRegions.defaultExitMargin, dy: -SurfaceHoverRegions.defaultExitMargin),
                "\(style): exit is the rule union + margin"
            )
        }
    }
}

// swiftlint:enable force_unwrapping
