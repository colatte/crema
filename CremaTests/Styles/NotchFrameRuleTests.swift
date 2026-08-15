import CoreGraphics
import Testing
@testable import Crema

/// Notch frame rule: pure function of
/// (state, ScreenGeometry). The surface anchors at the slit (top edge flush with
/// the screen top, centred IN THE SLIT) but descends below it into visible pixels;
/// the expanded rect fully contains the compact one, giving hover hysteresis. No AppKit.
@MainActor
struct NotchFrameRuleTests {

    private let style = NotchStyle()
    private let track = CoordinatorHarness.playingTrack()

    /// A notched 14" display: 1512-wide, 32 pt slit, aux areas of 663.5 pt each
    /// (slit width = 1512 − 663.5 − 663.5 = 185 pt).
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    /// The SAME panel as measured rather than rounded: 663 pt left of the slit and
    /// 664 right (StylePreview.notchedReference, the numbers the Settings picture
    /// draws). The fixture above splits the difference; this one keeps the
    /// hardware's own half point, and that half point is the whole test — a rule
    /// that finds the slit by the DISPLAY's centre lands half a point right of the
    /// cutout's, on live menu-bar pixels
    /// (docs/DECISIONS.md: the-slit-is-found-from-its-edges).
    private let asymmetric = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663,
        auxRight: 664
    )
    private let noNotch = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

    private var slitWidth: CGFloat { slitWidth(of: notched) }   // 185

    private func slitWidth(of geometry: ScreenGeometry) -> CGFloat {
        geometry.frame.width - geometry.auxLeft - geometry.auxRight
    }

    /// Every state that actually draws a surface — `.hidden` is a point and has no
    /// edges to compare against the cutout's.
    private var visibleStates: [PresentationState] {
        [
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .volume, value: 0.5)),
        ]
    }

    @Test func compactAnchorsAtTheSlitTuckedInsideIt() {
        let frame = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        #expect(frame.width == slitWidth - 2 * NotchMetrics.lateralInset)
        #expect(frame.midX == notched.frame.midX)                              // this fixture's slit is centred, so both centres agree
        #expect(frame.maxY == notched.frame.maxY)                              // top flush with the screen top
    }

    @Test func compactDescendsBelowTheSlitIntoVisiblePixels() {
        // The core fix: the surface is taller than the slit and its bottom
        // edge sits below the cutout, so content/hover land on real pixels — not
        // the camera dead zone (which caused the hidden content and hover flicker).
        let frame = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        #expect(frame.height == notched.safeTop + NotchMetrics.compactDrop)
        #expect(frame.height > notched.safeTop)
        let slitBottom = notched.frame.maxY - notched.safeTop
        #expect(frame.minY < slitBottom)   // extends past the slit's bottom edge
    }

    @Test func heightIsBuiltFromTheSlitNotTheMenuBar() {
        // Guards the menu-bar-vs-slit distinction: the height is derived from
        // safeTop (the slit) + the drop, never the taller menu-bar height.
        let frame = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: notched)
        #expect(frame.height == notched.safeTop + NotchMetrics.compactDrop)
    }

    @Test func hudUsesTheSameCompactFrame() {
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let hud = style.frame(for: .hud(SystemHUD(kind: .volume, value: 0.5)), on: notched)
        #expect(hud == compact)
    }

    @Test func everyStateNeverOvershootsTheSlit() {
        // Flush with the cutout is the calibrated ideal (lateralInset 0 — any
        // tuck reads recessed on hardware); an edge past the slit would land
        // on live pixels and cover the clickable menu bar. So: within, never
        // beyond. Asked of the asymmetric panel too, where a display-centred
        // rule overshoots the right edge by half a point.
        for geometry in [notched, asymmetric] {
            let slitLeft = geometry.frame.minX + geometry.auxLeft
            let slitRight = geometry.frame.maxX - geometry.auxRight
            for state in visibleStates {
                let frame = style.frame(for: state, on: geometry)
                #expect(frame.minX >= slitLeft)
                #expect(frame.maxX <= slitRight)
            }
        }
    }

    @Test func theSurfaceIsCentredInTheSlitNotInTheDisplay() throws {
        // One rule finds the cutout, and the surface, the click-invoke zone and
        // that rule's own rect are the same span of x. On the measured 663/664
        // panel the display's centre (756) and the slit's (755.5) differ, which
        // is what let the surface claim [663.5, 848.5] against a cutout ending at
        // 848 — half a point of antialiased edge on live menu-bar pixels.
        let slit = try #require(NotchStyle.slit(on: asymmetric))
        #expect(slit.midX != asymmetric.frame.midX, "the fixture must be asymmetric or it proves nothing")
        let zone = try #require(style.invokeZone(on: asymmetric))
        #expect(zone == slit)
        for state in visibleStates {
            let frame = style.frame(for: state, on: asymmetric)
            #expect(frame.midX == slit.midX)
            #expect(frame.minX == slit.minX)
            #expect(frame.maxX == slit.maxX)
        }
    }

    @Test func aFullWidthSafeAreaIsNotANotch() {
        // NSScreen.h documents both auxiliary rects as "empty if there are no
        // additional unobscured areas", so a top safe area with no aux coverage
        // describes an obscured strip spanning the display — not a cutout. Read as
        // one, the slit would be the whole 1512 pt: a display-wide surface welded
        // to the top edge, and an invoke zone over the entire menu bar, which the
        // panel captures the mouse inside for clicks Coordinator.invoke refuses.
        let fullWidthSafeArea = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32
        )
        #expect(NotchStyle.slit(on: fullWidthSafeArea) == nil)
        #expect(style.invokeZone(on: fullWidthSafeArea) == nil)
        // The declared→drawn resolver asks the same rule, so the picker, the
        // panels and this geometry cannot disagree about what is drawn here.
        #expect(Style.notch.resolved(on: fullWidthSafeArea) == .card)
        #expect(!Style.notch.isHonoured(on: fullWidthSafeArea))
        for state in visibleStates + [.hidden] {
            #expect(style.frame(for: state, on: fullWidthSafeArea) == CardStyle().frame(for: state, on: fullWidthSafeArea))
        }
    }

    @Test func expandedGrowsDownFromTheSameTopAnchor() {
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: notched)
        #expect(expanded.height > compact.height)
        #expect(expanded.midX == compact.midX)   // same center
        #expect(expanded.maxY == compact.maxY)   // same top edge (grows down)
        #expect(expanded.height == notched.safeTop + NotchMetrics.expandedDrop)
    }

    @Test func expandedContainsCompactForHoverHysteresis() {
        // Once expanded, the exit boundary is the (larger) expanded rect, which
        // fully contains the compact entry area — spatial hysteresis that, with
        // hover-intent + debounce, kills the open/close flicker.
        let compact = style.frame(for: .nowPlaying(track, expanded: false), on: notched)
        let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: notched)
        #expect(expanded.contains(compact))
    }

    @Test func hiddenCollapsesToThePointAtTheSlit() throws {
        let frame = style.frame(for: .hidden, on: notched)
        #expect(frame.isEmpty)
        #expect(frame.midX == notched.frame.midX)
        #expect(frame.maxY == notched.frame.maxY)
        // The point the show/hide animation converges on is the CUTOUT's centre,
        // which on the measured 663/664 panel is not the display's.
        let slit = try #require(NotchStyle.slit(on: asymmetric))
        #expect(style.frame(for: .hidden, on: asymmetric).midX == slit.midX)
    }

    @Test func fallsBackToTheCardOnADisplayWithoutANotch() {
        // No physical notch: the rule degrades to the card geometry (defensive;
        // the WindowManager also resolves notch→card on non-notch displays).
        let states: [PresentationState] = [
            .hidden,
            .nowPlaying(track, expanded: false),
            .nowPlaying(track, expanded: true),
            .hud(SystemHUD(kind: .screenBrightness, value: 0.8)),
        ]
        for state in states {
            #expect(style.frame(for: state, on: noNotch) == CardStyle().frame(for: state, on: noNotch))
        }
    }

    @Test func invokeZoneIsExactlyThePhysicalSlit() {
        // The click-invoke zone must be dead territory only: the slit rect,
        // never the compact frame (whose drop band overlaps live content
        // below the menu bar) and never the flanking menu-bar areas. Written out
        // from the aux edges rather than read back from the rule, and asked of the
        // asymmetric panel too — the zone is where clicks are captured, so it may
        // not inherit a centre-derived guess of where the cutout is.
        for geometry in [notched, asymmetric] {
            #expect(style.invokeZone(on: geometry) == CGRect(
                x: geometry.frame.minX + geometry.auxLeft,
                y: geometry.frame.maxY - geometry.safeTop,
                width: slitWidth(of: geometry),
                height: geometry.safeTop
            ))
        }
        // Without a slit there is nothing dead to claim.
        #expect(style.invokeZone(on: noNotch) == nil)
        // The floating styles never click-invoke: their regions sit over
        // live app content.
        #expect(CardStyle().invokeZone(on: noNotch) == nil)
        #expect(ClassicStyle().invokeZone(on: noNotch) == nil)
        #expect(Style.notch.invokeZone(on: notched) == style.invokeZone(on: notched))
    }

    @Test func frameRuleIsDeterministic() {
        let state = PresentationState.nowPlaying(track, expanded: true)
        // A pure rule is deterministic: the same inputs must yield an equal frame.
        // swiftlint:disable:next identical_operands
        #expect(style.frame(for: state, on: notched) == style.frame(for: state, on: notched))
    }

    @Test func lateralEdgesSnapInwardToDevicePixels() {
        // Fractional aux widths (a scale mode artifact) must not leave the
        // surface's antialiased edge outside the cutout: both edges land on
        // the @2x pixel grid, rounded inward (never past the slit).
        let fractional = ScreenGeometry(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeTop: 32,
            auxLeft: 663.4,
            auxRight: 663.4
        )
        let rawSlitWidth = fractional.frame.width - fractional.auxLeft - fractional.auxRight

        let frame = style.frame(for: .nowPlaying(track, expanded: false), on: fractional)

        #expect((frame.minX * fractional.scale).truncatingRemainder(dividingBy: 1) == 0)
        #expect((frame.maxX * fractional.scale).truncatingRemainder(dividingBy: 1) == 0)
        #expect(frame.width <= rawSlitWidth - 2 * NotchMetrics.lateralInset)
    }

    @Test func theMorphNeverMovesTheLateralEdges() {
        // The hover shimmer was exactly this: any lateral drift between the
        // states re-rasterizes the edge against the cutout mid-animation.
        for geometry in [notched, ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeTop: 32, auxLeft: 663.4, auxRight: 663.4)] {
            let compact = style.frame(for: .nowPlaying(track, expanded: false), on: geometry)
            let expanded = style.frame(for: .nowPlaying(track, expanded: true), on: geometry)
            #expect(compact.minX == expanded.minX)
            #expect(compact.maxX == expanded.maxX)
        }
    }
}
