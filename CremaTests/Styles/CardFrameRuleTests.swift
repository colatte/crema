import CoreGraphics
import Testing
@testable import Crema

/// Card frame rule: pure function of (state, ScreenGeometry). One width for
/// every state — the card's identity is vertical growth — top-anchored below
/// the safe area, centered.
@MainActor
struct CardFrameRuleTests {

    private let style = CardStyle()
    private let track = CoordinatorHarness.playingTrack()
    private let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))

    @Test func everyStateSharesTheTopAnchorAndNowPlayingSharesTheCeiling() {
        let states: [PresentationState] = [
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        for state in states {
            let frame = style.frame(for: state, on: geometry)
            #expect(frame.midX == geometry.frame.midX)
            #expect(frame.maxY == geometry.frame.maxY - CardMetrics.topMargin)
        }
        // Growth stays vertical: compact and expanded share the same width
        // ceiling in the rule (the view hugs below it); the HUD is its own
        // fixed strip.
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: geometry)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: geometry)
        #expect(compact.width == expanded.width)
        #expect(style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: geometry).width == CardMetrics.hud.width)
    }

    @Test func adaptiveBoundsAreOrderedAndContainedByTheRule() {
        #expect(CardMetrics.compactMinWidth < CardMetrics.compactMaxWidth)
        #expect(CardMetrics.compactMaxWidth == CardMetrics.compact.width)
        #expect(CardMetrics.expandedMinWidth < CardMetrics.expandedMaxWidth)
        #expect(CardMetrics.expandedMaxWidth == CardMetrics.expanded.width)
    }

    @Test func expandedGrowsDownOnly() {
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: geometry)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: geometry)
        #expect(expanded.height > compact.height)
        #expect(expanded.width == compact.width)
        #expect(expanded.maxY == compact.maxY)
        #expect(expanded.contains(compact))   // hover hysteresis
    }

    @Test func cardClearsTheNotchSafeArea() {
        let notched = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32,
            auxLeft: 663.5,
            auxRight: 663.5
        )
        let frame = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: notched)
        #expect(frame.maxY == notched.frame.maxY - notched.safeTop - CardMetrics.topMargin)
    }

    @Test func frameFollowsTheScreenOrigin() {
        let second = ScreenGeometry(frame: CGRect(x: -1000, y: 500, width: 1200, height: 800))
        let frame = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: second)
        #expect(frame.midX == second.frame.midX)
        #expect(frame.maxY == second.frame.maxY - CardMetrics.topMargin)
    }

    @Test func hiddenCollapsesToThePointAtTheAnchor() {
        let frame = style.frame(for: .hidden, on: geometry)
        #expect(frame.isEmpty)
        #expect(frame.midX == geometry.frame.midX)
        #expect(frame.maxY == geometry.frame.maxY - CardMetrics.topMargin)
    }

    @Test func sizesAreFixedRegardlessOfContent() {
        let short = NowPlaying(title: "Ay", isPlaying: true, position: 0)
        let long = NowPlaying(title: "The Continuing Story of Bungalow Bill", artist: "The Beatles", isPlaying: true, position: 0)
        for expanded in [false, true] {
            #expect(
                style.frame(for: .nowPlaying(short, expanded: expanded), on: geometry)
                    == style.frame(for: .nowPlaying(long, expanded: expanded), on: geometry)
            )
        }
    }
}
