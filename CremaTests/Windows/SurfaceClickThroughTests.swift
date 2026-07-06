import CoreGraphics
import Testing
@testable import Crema

/// The fixed window overlaps the menu bar around the slit; this contract is
/// what keeps it usable — only the visible surface captures the mouse, and a
/// hidden surface captures nothing at all.
struct SurfaceClickThroughTests {

    private let track = NowPlaying(title: "Breathe", isPlaying: true, position: 0)
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )

    @Test func aHiddenSurfaceCapturesNothing() {
        let hidden = NotchStyle().frame(for: .hidden, on: notched)
        let window = NotchStyle().windowFrame(on: notched)
        // Even a point dead-center in the fixed window falls through.
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: window.midX, y: window.midY), surface: hidden))
    }

    @Test func theCompactSurfaceCapturesOnlyItself() {
        let style = NotchStyle()
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let window = style.windowFrame(on: notched)

        // Inside the visible surface: captured.
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: compact.midX, y: compact.midY), surface: compact))

        // Menu-bar pixels beside the slit, still inside the fixed window: the
        // click must pass through — this is the "menus stay clickable" contract.
        let besideSlit = CGPoint(x: compact.minX - 4, y: notched.frame.maxY - 12)
        #expect(window.contains(besideSlit))
        #expect(!SurfaceClickThrough.isInteractive(besideSlit, surface: compact))

        // Below the compact band (where only the expanded surface reaches).
        let belowCompact = CGPoint(x: compact.midX, y: compact.minY - 10)
        #expect(window.contains(belowCompact))
        #expect(!SurfaceClickThrough.isInteractive(belowCompact, surface: compact))
    }

    @Test func theInteractiveRegionFollowsTheSurfaceSize() {
        let style = NotchStyle()
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: notched)

        // A point that falls through beside the compact band captures once the
        // surface expands over it.
        let belowCompact = CGPoint(x: compact.midX, y: compact.minY - 10)
        #expect(expanded.contains(belowCompact))
        #expect(!SurfaceClickThrough.isInteractive(belowCompact, surface: compact))
        #expect(SurfaceClickThrough.isInteractive(belowCompact, surface: expanded))
    }

    @Test func reportedSurfaceRectIsTopCenterAnchoredInTheWindow() {
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let window = CardStyle().windowFrame(on: plain)
        let size = CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height)

        let rect = SurfaceClickThrough.surfaceRect(size: size, window: window, anchor: .top)

        #expect(rect.size == size)
        #expect(rect.midX == window.midX)
        #expect(rect.maxY == window.maxY)   // top-anchored, exactly where the views draw
    }

    @Test func reportedSurfaceRectBottomAnchorsForTheClassicBlock() {
        // Classic sits on its bottom line and grows up, so its reported region
        // pins to the window's bottom — a view-only-shortened surface stays on
        // the anchor line instead of floating at the top.
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let window = ClassicStyle().windowFrame(on: plain)
        let full = ClassicMetrics.expanded
        let shortened = CGSize(width: full.width, height: full.height - ClassicMetrics.controlsSectionHeight)

        let rect = SurfaceClickThrough.surfaceRect(size: shortened, window: window, anchor: .bottom)

        #expect(rect.size == shortened)
        #expect(rect.midX == window.midX)
        #expect(rect.minY == window.minY)   // bottom-anchored on the classic line
        // The full-height region would have reached higher; the shortened one
        // doesn't cover that top band, so clicks there fall through.
        #expect(rect.maxY < window.minY + full.height)
    }

    @Test func aNarrowAdaptiveSurfaceCapturesOnlyItsRenderedWidth() {
        // The hugging card can render narrower than its rule frame (the
        // ceiling): clicks in the ceiling band beside the visible surface must
        // pass through — the region follows the rendered size.
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let style = CardStyle()
        let window = style.windowFrame(on: plain)
        let ruleFrame = style.frame(for: .nowPlaying(track, expanded: false), on: plain)
        let narrow = SurfaceClickThrough.surfaceRect(
            size: CGSize(width: CardMetrics.compactMinWidth, height: CardMetrics.compact.height),
            window: window,
            anchor: .top
        )

        let besideNarrow = CGPoint(x: narrow.maxX + 10, y: narrow.midY)
        #expect(ruleFrame.contains(besideNarrow))   // inside the ceiling band
        #expect(!SurfaceClickThrough.isInteractive(besideNarrow, surface: narrow))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: narrow.midX, y: narrow.midY), surface: narrow))
    }

    @Test func theCardFollowsTheSameContract() {
        let style = CardStyle()
        let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: plain)
        let hidden = style.frame(for: .hidden, on: plain)

        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: compact.midX, y: compact.midY), surface: compact))
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: compact.maxX + 8, y: compact.midY), surface: compact))
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: compact.midX, y: compact.midY), surface: hidden))
    }
}
