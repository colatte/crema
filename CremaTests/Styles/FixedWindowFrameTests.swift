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

    /// The concrete rule each enum case must dispatch to. A second table on
    /// purpose: the production switch is only worth asserting against something
    /// written independently of it, and an exhaustive switch here means a fourth
    /// skin cannot arrive without deciding what it answers.
    private func rule(for style: Style) -> any PresentationStyle {
        switch style {
        case .notch: NotchStyle()
        case .card: CardStyle()
        case .classic: ClassicStyle()
        }
    }

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

    @Test func everyStyleDispatchesItsFixedWindowToItsOwnRule() {
        // Asking whether the enum's `windowFrame` is non-nil asserted nothing:
        // every skin's requirement returns a non-optional CGRect, so no case —
        // present or future — could ever answer nil, and a case wired to the
        // WRONG skin stayed green. The rect is what a mis-wired switch fails,
        // and it is checked for all three cases (classic was never covered).
        for style in Style.allCases {
            let geometry = style == .notch ? notched : plain
            #expect(style.windowFrame(on: geometry) == rule(for: style).windowFrame(on: geometry), "\(style)")
            #expect(style.windowFrame(on: geometry)?.isEmpty == false, "\(style)")
        }
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

    @Test func stateSizesAndTheFixedWindowComeFromTheSameRule() throws {
        // This pair used to be asserted as a nil-partition — "both present or
        // both absent" — which no case can fail in either direction: each enum
        // accessor wraps a rule that always returns a value, so the comparison
        // read false == false forever. The concern behind it is real, and this is
        // it: a skin sizes its surface inside its fixed window, so the two
        // answers must come from the SAME skin and every state must fit — a
        // surface larger than its window is the clip at the window edge that the
        // fixed-window model exists to remove.
        for style in Style.allCases {
            for geometry in [plain, notched] {
                let window = try #require(style.windowFrame(on: geometry), "\(style)")
                let sizes = try #require(style.stateSizes(on: geometry), "\(style)")
                #expect(sizes == rule(for: style).stateSizes(on: geometry), "\(style)")
                for size in [sizes.compact, sizes.expanded, sizes.hud] {
                    #expect(size.width <= window.width, "\(style)")
                    #expect(size.height <= window.height, "\(style)")
                }
            }
        }
    }
}
