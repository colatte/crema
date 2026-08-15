import CoreGraphics
import Testing
@testable import Crema

/// Classic frame rule: pure function of (state, ScreenGeometry). All
/// states share the native OSD's bottom line and grow upward, centered.
@MainActor
struct ClassicFrameRuleTests {

    private let style = ClassicStyle()
    private let track = CoordinatorHarness.playingTrack()
    private let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))

    @Test func everyStateSitsOnTheBottomLineCentered() {
        let states: [PresentationState] = [
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
        for state in states {
            let frame = style.frame(for: state, on: geometry)
            #expect(frame.minY == geometry.frame.minY + ClassicMetrics.bottomMargin)
            #expect(frame.midX == geometry.frame.midX)
        }
    }

    @Test func statesUseTheirMetricSizes() {
        #expect(style.frame(for: .nowPlaying(track, expanded: false), on: geometry).size == ClassicMetrics.compact)
        #expect(style.frame(for: .nowPlaying(track, expanded: true), on: geometry).size == ClassicMetrics.expanded)
        #expect(style.frame(for: .hud(SystemHUD(kind: .screenBrightness, value: 0.3)), on: geometry).size == ClassicMetrics.hud)
    }

    @Test func expandedContainsCompactForHoverHysteresis() {
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: geometry)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: geometry)
        #expect(expanded.contains(compact))
    }

    /// Pinned-latent fence (docs/CONTRACTS.md: G2), kept past the shortcut it
    /// was written against: ClassicStyle.windowFrame once built the fixed window
    /// from ONLY the expanded state's rule frame, on the silent assumption that
    /// expanded dominates compact AND hud on both axes (true by metric
    /// coincidence: expanded 230×224 vs hud 200×200 vs compact 170×170). The
    /// window now unions the three states, so nothing clips if the assumption
    /// breaks — but the Classic's headroom and anchor arithmetic still assume
    /// expanded is the tallest, so the fence stays loud: grow ClassicMetrics.hud
    /// or .compact past expanded on either axis and this fails first.
    @Test func expandedDominatesEveryOtherStateFrame_pinnedLatentG2() {
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: geometry)
        let others: [PresentationState] = [
            .nowPlaying(track, expanded: false),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
            .hud(SystemHUD(kind: .screenBrightness, value: 1)),
        ]
        for state in others {
            let frame = style.frame(for: state, on: geometry)
            #expect(expanded.contains(frame), "\(state) escapes the expanded-derived window")
            // Each axis independently: a taller-but-narrower future HUD would
            // still clip even if area looked safe.
            #expect(frame.width <= expanded.width)
            #expect(frame.height <= expanded.height)
        }
        // The window unions every state, so it holds them by construction; this
        // half is the contract the union must never lose.
        let window = style.windowFrame(on: geometry)
        for state in others {
            #expect(window.contains(style.frame(for: state, on: geometry)))
        }
    }

    @Test func hiddenCollapsesToThePointOnTheAnchorLine() {
        let frame = style.frame(for: .hidden, on: geometry)
        #expect(frame.isEmpty)
        #expect(frame.midX == geometry.frame.midX)
        #expect(frame.minY == geometry.frame.minY + ClassicMetrics.bottomMargin)
    }

    @Test func frameFollowsTheScreenOrigin() {
        let second = ScreenGeometry(frame: CGRect(x: 2000, y: -300, width: 1200, height: 800))
        let frame = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: second)
        #expect(frame.midX == second.frame.midX)
        #expect(frame.minY == second.frame.minY + ClassicMetrics.bottomMargin)
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
