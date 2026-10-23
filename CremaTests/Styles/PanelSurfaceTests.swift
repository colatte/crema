import CoreGraphics
import SwiftUI
import Testing
@testable import Crema

/// What each panel draws: a skin's own panel draws both layers, and only the Card
/// with its HUD off the card's own spot splits into a panel per layer. The split
/// panels keep the Card's rules, except where the HUD sits — which is the HUD's own
/// rule, hung from the top of a window of its own exactly like every Card surface.
struct PanelSurfaceTests {

    private let plain = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1000, height: 600))
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663.5,
        auxRight: 663.5
    )
    private let offset = ScreenGeometry(frame: CGRect(x: -1280, y: 400, width: 1280, height: 800))
    private var geometries: [ScreenGeometry] { [plain, notched, offset] }

    private let track = NowPlaying(title: "Breathe", artist: "Pink Floyd", isPlaying: true, position: 10, duration: 169)
    private let hud = SystemHUD(kind: .volume, value: 0.5)
    private var offSpot: [HUDPlacement] { HUDPlacement.allCases.filter { $0 != .topCenter } }

    @Test func onlyTheCardSplitsAndOnlyWithItsHUDOffItsOwnSpot() {
        for style in Style.allCases {
            for placement in HUDPlacement.allCases {
                let surfaces = PanelSurface.surfaces(for: style, hudPlacement: placement)
                if style == .card, placement != .topCenter {
                    #expect(surfaces == [.cardNowPlaying, .cardHUD(placement)], "\(style) \(placement)")
                } else {
                    #expect(surfaces == [.skin(style)], "\(style) \(placement)")
                }
            }
        }
    }

    @Test func aSplitPanelDrawsOneLayerOfTheCard() {
        for style in Style.allCases {
            #expect(PanelSurface.skin(style).layers == .both)
            #expect(PanelSurface.skin(style).style == style)
            #expect(PanelSurface.skin(style).hudAxis == .horizontal)
        }
        #expect(PanelSurface.cardNowPlaying.layers == .nowPlaying)
        #expect(PanelSurface.cardNowPlaying.style == .card)
        for placement in offSpot {
            let surface = PanelSurface.cardHUD(placement)
            #expect(surface.layers == .hud, "\(placement)")
            #expect(surface.style == .card, "\(placement)")
            #expect(surface.hudAxis == placement.axis, "\(placement)")
        }
    }

    @Test func aPanelDrawingTheAppearanceKeepsItsSkinsRules() {
        // A mis-wired case returns a rect all the same; only its value tells which
        // rule it was wired to.
        let states: [PresentationState] = [.hidden, .nowPlaying(track, expanded: false), .nowPlaying(track, expanded: true), .hud(hud)]
        let surfaces = Style.allCases.map(PanelSurface.skin) + [.cardNowPlaying]
        for surface in surfaces {
            for geometry in geometries {
                for state in states {
                    #expect(surface.frame(for: state, on: geometry) == surface.style.frame(for: state, on: geometry), "\(surface)")
                }
                #expect(surface.windowFrame(on: geometry) == surface.style.windowFrame(on: geometry), "\(surface)")
                #expect(surface.hoverRegions(on: geometry) == surface.style.hoverRegions(on: geometry), "\(surface)")
                #expect(surface.stateSizes(on: geometry) == surface.style.stateSizes(on: geometry), "\(surface)")
                #expect(surface.invokeZone(on: geometry) == surface.style.invokeZone(on: geometry), "\(surface)")
            }
        }
    }

    @Test func theHUDsOwnPanelDrawsItAtItsPlacementAndNothingElse() {
        for placement in offSpot {
            let surface = PanelSurface.cardHUD(placement)
            for geometry in geometries {
                let spot = CardStyle.hudFrame(at: placement, on: geometry)
                #expect(surface.frame(for: .hud(hud), on: geometry) == spot, "\(placement)")
                // Nothing on this panel collapses onto the line the HUD hangs from.
                for state in [PresentationState.hidden, .nowPlaying(track, expanded: false)] {
                    let empty = surface.frame(for: state, on: geometry)
                    #expect(empty.isEmpty, "\(placement)")
                    #expect(empty.origin == CGPoint(x: spot.midX, y: spot.maxY), "\(placement)")
                }
                #expect(surface.stateSizes(on: geometry)?.hud == CardMetrics.hudSize(for: placement.axis), "\(placement)")
                #expect(surface.invokeZone(on: geometry) == nil, "\(placement)")
            }
        }
    }

    @Test func theHUDHangsFromTheTopOfItsOwnWindowExactlyOnItsSpot() throws {
        // The Card's view hangs its surface top-centred in the fixed window, so the
        // window is what puts the HUD on its spot: a window off by a point puts the
        // bar off by a point, with every frame rule still right.
        for placement in offSpot {
            let surface = PanelSurface.cardHUD(placement)
            for geometry in geometries {
                let spot = CardStyle.hudFrame(at: placement, on: geometry)
                let window = surface.windowFrame(on: geometry)
                let drawn = try SurfaceClickThrough.surfaceRect(
                    size: #require(surface.stateSizes(on: geometry)).hud,
                    window: window,
                    anchor: surface.surfaceVerticalAnchor
                )
                #expect(drawn == spot, "\(placement)")
                // Headroom for the open spring, sideways and down; the top stays pinned.
                #expect(window.minX == spot.minX - SurfaceAnimation.overshootHeadroom, "\(placement)")
                #expect(window.maxX == spot.maxX + SurfaceAnimation.overshootHeadroom, "\(placement)")
                #expect(window.minY == spot.minY - SurfaceAnimation.overshootHeadroom, "\(placement)")
                #expect(window.maxY == spot.maxY, "\(placement)")
            }
        }
    }

    @Test func thePointerHoldsTheHUDWhereItIs() throws {
        let comfort = SurfaceHoverRegions.comfortMargin
        for placement in offSpot {
            let surface = PanelSurface.cardHUD(placement)
            for geometry in geometries {
                let spot = CardStyle.hudFrame(at: placement, on: geometry)
                let regions = try #require(surface.hoverRegions(on: geometry), "\(placement)")
                #expect(regions.enter == spot.insetBy(dx: -comfort, dy: -comfort), "\(placement)")
                #expect(regions.exit.contains(regions.enter), "\(placement)")
            }
            #expect(surface.hoverCommit == .immediate)
        }
    }
}
