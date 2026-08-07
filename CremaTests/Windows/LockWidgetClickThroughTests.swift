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
        // 340 wide, 152 tall, centred, 96 pt off the bottom — so in SwiftUI's
        // frame it starts 900 - 96 - 152 = 652 pt down.
        let card = CGRect(x: 550, y: 652, width: 340, height: 152)
        let rect = LockWidgetClickThrough.screenRect(cardInWindow: card, window: screen)
        // AppKit space: y counts up from the bottom, so the card's baseline is
        // exactly its bottom inset.
        #expect(rect == CGRect(x: 550, y: 96, width: 340, height: 152))
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

    /// Where the login UI actually is, on the 1440×900 panel above. The middle
    /// of the display and the low centre — which is why "the card's column" and
    /// "the card" are not the same answer.
    @Test func theLoginUIsOwnPixelsAreNeverCaptured() {
        let card = CGRect(x: 550, y: 652, width: 340, height: 152)
        let region = LockWidgetClickThrough.screenRect(cardInWindow: card, window: screen)

        // The password field and the avatar sit centred, well above the card.
        for y in [450.0, 380.0, 520.0] {
            #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: y), surface: region))
        }
        // The clock, at the top of the display, directly above the card's column
        // — the case that made the bug obvious: it expanded the cover.
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 860), surface: region))
        // And the corners, which belong to nobody but must not belong to us.
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 4, y: 896), surface: region))
    }

    @Test func theCardItselfIsCaptured() {
        let card = CGRect(x: 550, y: 652, width: 340, height: 152)
        let region = LockWidgetClickThrough.screenRect(cardInWindow: card, window: screen)
        // Its middle, and a point just inside each edge — the play button and the
        // scrubber live near those.
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 172), surface: region))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 551, y: 97), surface: region))
        #expect(SurfaceClickThrough.isInteractive(CGPoint(x: 889, y: 247), surface: region))
    }

    @Test func theExpandedCardIsNarrowerAndTheGapGoesBackToTheLoginUI() {
        // Expanding shrinks the card to 300 pt and gives the cover the screen,
        // but the cover is drawn, not clickable: the only pixels that ever
        // capture are the card's, in BOTH states. So a point that was inside the
        // collapsed card and is outside the expanded one goes back to the shield.
        let collapsed = LockWidgetClickThrough.screenRect(
            cardInWindow: CGRect(x: 550, y: 652, width: 340, height: 152), window: screen
        )
        let expanded = LockWidgetClickThrough.screenRect(
            cardInWindow: CGRect(x: 570, y: 652, width: 300, height: 152), window: screen
        )
        let edge = CGPoint(x: 560, y: 172)
        #expect(SurfaceClickThrough.isInteractive(edge, surface: collapsed))
        #expect(!SurfaceClickThrough.isInteractive(edge, surface: expanded))
        // The middle of the display stays the login UI's in the expanded state
        // too — that is the invariant, not a property of one state.
        #expect(!SurfaceClickThrough.isInteractive(CGPoint(x: 720, y: 450), surface: expanded))
    }
}
