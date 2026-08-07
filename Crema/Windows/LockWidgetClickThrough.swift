import CoreGraphics

/// Which pixels of the lock surface may take a mouse click.
///
/// The invariant, and it is the whole file: **only the card ever captures.**
/// Everything else the window covers belongs to the password field, the avatar
/// and the Cancel/Switch-User buttons, and a window that captures there does not
/// misroute a click — it takes the login UI away from someone standing at a
/// locked Mac. So the panel is born click-through and the interactive region is
/// only ever what the card actually draws, in both states: expanded, the cover
/// fills the display but the card is still down there to click, so there is
/// always a way back without making the hidden login UI clickable-but-invisible.
///
/// The rect comes from the RENDERED card rather than a rule, for the reason
/// `SurfaceClickThrough` already gives about the desktop skins: a rule frame
/// cannot know a surface the view shortened on its own, and a hit region
/// computed twice is a hit region that drifts.
enum LockWidgetClickThrough {
    /// SwiftUI reports a frame in the hosting window's space — origin at the
    /// window's TOP-left, y growing down. `NSEvent.mouseLocation` speaks AppKit
    /// global screen space — origin at the bottom-left of the primary display,
    /// y growing up. This is the flip between them, and the window's own origin
    /// is what carries it onto a secondary display.
    ///
    /// An empty input stays empty rather than becoming a zero-sized rect at some
    /// coordinate: `SurfaceClickThrough.isInteractive` refuses an empty surface,
    /// and that refusal is what makes "no card on screen" mean "capture
    /// nothing".
    static func screenRect(cardInWindow: CGRect, window: CGRect) -> CGRect {
        guard !cardInWindow.isEmpty else { return .zero }
        return CGRect(
            x: window.minX + cardInWindow.minX,
            y: window.maxY - cardInWindow.maxY,
            width: cardInWindow.width,
            height: cardInWindow.height
        )
    }
}
