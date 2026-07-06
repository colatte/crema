import CoreGraphics
import Testing
@testable import Crema

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
}
