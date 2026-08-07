import CoreGraphics
import Testing
@testable import Crema

/// The coordinate flip, and the rule that decides whether the lock screen keeps
/// its own clicks.
///
/// This is the only part of that decision a test can own — whether the
/// WindowServer routes a click to a click-through window needs a locked Mac —
/// but it is the part that was wrong: the shipped version captured everywhere,
/// including the password field, and the comment beside it claimed otherwise.
struct LockWidgetClickThroughTests {

    /// A 1440×900 built-in panel at the origin, the way AppKit reports it.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func theRectIsFlippedOntoTheScreenTheWindowCovers() {
        // SwiftUI hands back window space: origin top-left, y down. The card is
        // 340 wide, 152 tall, centred, 300 pt off the bottom — so in SwiftUI's
        // frame it starts 900 - 300 - 152 = 448 pt down.
        let card = CGRect(x: 550, y: 448, width: 340, height: 152)
        let rect = LockWidgetClickThrough.screenRect(cardInWindow: card, window: screen)
        // AppKit space: y counts up from the bottom, so the card's baseline is
        // exactly its bottom inset.
        #expect(rect == CGRect(x: 550, y: 300, width: 340, height: 152))
    }

    @Test func theWindowsOwnOriginCarriesItOntoASecondaryDisplay() {
        // A display to the right of and below the primary — the arrangement that
        // makes a forgotten origin land the hit region on the wrong screen.
        let external = CGRect(x: 1440, y: -180, width: 2560, height: 1440)
        let card = CGRect(x: 1110, y: 1192, width: 340, height: 152)
        let rect = LockWidgetClickThrough.screenRect(cardInWindow: card, window: external)
        #expect(rect == CGRect(x: 2550, y: -84, width: 340, height: 152))
        // Whatever the arrangement, the region has to land inside the display it
        // was measured on.
        #expect(external.contains(rect))
    }

    @Test func anEmptyCardCapturesNothingRatherThanAPointSomewhere() {
        // The resting state whenever no media is playing, and the value the view
        // publishes the moment the card leaves. A zero-SIZED rect at a real
        // coordinate would still be a rect; this has to be refused outright.
        let rect = LockWidgetClickThrough.screenRect(cardInWindow: .zero, window: screen)
        #expect(rect == .zero)
        #expect(!SurfaceClickThrough.isInteractive(.zero, surface: rect))
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 450), surface: rect))
    }

    // MARK: - What the lock screen keeps

    /// Where the login UI actually is, measured on hardware 2026-08-07 with
    /// `scripts/probes/lockscreen-geometry.swift`: the avatar, the name and the
    /// password field own the BOTTOM strip, roughly up to y=250, and they never
    /// leave the centre column. The middle of the display is empty — which is
    /// the opposite of what the first version of this file assumed, and the
    /// reason the card used to be drawn on top of the password field.
    private enum Login {
        static let top: CGFloat = 250
    }

    /// The collapsed card as it now ships: 340×152, centred, resting on the
    /// floor of the measured clear band at 300 pt.
    private var collapsed: CGRect {
        LockWidgetClickThrough.screenRect(
            cardInWindow: CGRect(x: 550, y: 448, width: 340, height: 152), window: screen
        )
    }

    /// The expanded tile: 300×300, centred on the display, which is exactly the
    /// square the ruler proved clear.
    private var expanded: CGRect {
        LockWidgetClickThrough.screenRect(
            cardInWindow: CGRect(x: 570, y: 300, width: 300, height: 300), window: screen
        )
    }

    @Test func neitherStateReachesDownIntoTheLoginStrip() {
        // The whole point of the placement, asserted on the rects rather than on
        // the constants: a hit region that dips below the login's top edge is a
        // click taken from the password field.
        #expect(collapsed.minY >= Login.top)
        #expect(expanded.minY >= Login.top)
        for y in stride(from: 4.0, to: Login.top, by: 40) {
            #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: y), surface: collapsed))
            #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: y), surface: expanded))
        }
    }

    @Test func theClockAtTheTopIsNeverCaptured() {
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 860), surface: collapsed))
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 860), surface: expanded))
        // And the corners, which belong to nobody but must not belong to us.
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 4, y: 896), surface: collapsed))
    }

    @Test func theSurfaceItselfIsCapturedInBothStates() {
        // Collapsed: its middle and a point just inside each edge — the play
        // button and the scrubber live near those.
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 376), surface: collapsed))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 551, y: 301), surface: collapsed))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 889, y: 451), surface: collapsed))

        // Expanded, the COVER is the surface — the controls sit on it. That is
        // the difference from the version this replaced, where the big cover was
        // a picture that deliberately ignored every click aimed at it while
        // covering the login UI it was refusing to capture for.
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 450), surface: expanded))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 590), surface: expanded))
    }

    @Test func expandingNeverWidensTheHitRegionSideways() {
        // The tile is narrower than the card, so expanding can only ever GIVE
        // pixels back to the shield on the x axis. A point inside the collapsed
        // card's flank must fall through once it is expanded.
        let flank = CGPoint(x: 560, y: 376)
        #expect(SurfaceClickThrough.isInteractive(flank, surface: collapsed))
        #expect(!SurfaceClickThrough.isInteractive(flank, surface: expanded))
        #expect(expanded.width <= collapsed.width)
    }
}
