import CoreGraphics
import Testing
@testable import Crema

/// The fixed window must contain every state the view can animate through (or
/// the morph clips at the window edge — the artifact the fixed-window model
/// exists to kill), and its top edge must sit exactly where the rule anchors
/// the surface, or the anchor shifts on screen.
struct FixedWindowFrameTests {

    private let track = NowPlaying(title: "Breathe", isPlaying: true, position: 0)
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))

    @Test func containsEveryStateFrame() {
        for (style, geometry): (any PresentationStyle, ScreenGeometry) in [(NotchStyle(), notched), (CardStyle(), plain), (ClassicStyle(), plain)] {
            let window = style.windowFrame(on: geometry)
            #expect(window.contains(style.frame(for: .nowPlaying(track, expanded: false), on: geometry)))
            #expect(window.contains(style.frame(for: .nowPlaying(track, expanded: true), on: geometry)))
            #expect(window.contains(style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: geometry)))
        }
    }

    @Test func topEdgeStaysPinnedToTheRuleAnchor() {
        let expanded = NotchStyle().frame(for: .nowPlaying(track, expanded: true), on: notched)
        let window = NotchStyle().windowFrame(on: notched)
        #expect(window.maxY == expanded.maxY)
        #expect(window.midX == expanded.midX)
    }

    @Test func headroomExtendsSidewaysAndDownOnly() {
        // The card's expanded ceiling spans every other state, so the window
        // is that frame padded sideways and down; the top edge stays pinned.
        let expanded = CardStyle().frame(for: .nowPlaying(track, expanded: true), on: plain)
        let window = CardStyle().windowFrame(on: plain)
        #expect(window.minX == expanded.minX - SurfaceAnimation.overshootHeadroom)
        #expect(window.maxX == expanded.maxX + SurfaceAnimation.overshootHeadroom)
        #expect(window.minY == expanded.minY - SurfaceAnimation.overshootHeadroom)
        #expect(window.maxY == expanded.maxY)
    }

    @Test func everyStyleHasAFixedWindow() {
        for style in Style.allCases {
            #expect(style.windowFrame(on: style == .notch ? notched : plain) != nil, "\(style)")
        }
        #expect(Style.notch.windowFrame(on: notched) == NotchStyle().windowFrame(on: notched))
        #expect(Style.card.windowFrame(on: plain) == CardStyle().windowFrame(on: plain))
    }

    @Test func classicWindowPinsTheBottomAnchor() {
        // The classic block sits on the native OSD line and grows upward, so
        // its headroom must go up — a moved bottom edge would shift the anchor.
        let expanded = ClassicStyle().frame(for: .nowPlaying(track, expanded: true), on: plain)
        let window = ClassicStyle().windowFrame(on: plain)
        #expect(window.minY == expanded.minY)
        #expect(window.maxY == expanded.maxY + SurfaceAnimation.overshootHeadroom)
        #expect(window.contains(ClassicStyle().frame(for: .nowPlaying(track, expanded: false), on: plain)))
        #expect(window.contains(ClassicStyle().frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: plain)))
    }

    @Test func fixedWindowAndStateSizesArePartitionedTogether() {
        // A skin that sizes its own surface needs both (the view sizes inside
        // the fixed window); a window-filling view needs neither. Half-
        // adopting silently reintroduces the resize race.
        for style in Style.allCases {
            for geometry in [plain, notched] {
                #expect((style.stateSizes(on: geometry) == nil) == (style.windowFrame(on: geometry) == nil))
            }
        }
    }
}
