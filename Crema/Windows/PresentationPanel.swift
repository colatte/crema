import CoreGraphics

/// Thin seam over the actual window so the WindowManager's logic
/// (reconciliation, frame math, style resolution) is testable without AppKit.
/// The real implementation wraps an NSPanel.
@MainActor
protocol PresentationPanel: AnyObject {
    /// Applies a frame in AppKit global screen coordinates (see ScreenTranslation).
    /// `hoverArmed`: whether the pointer should drive this panel's hover —
    /// armed only while a surface is visible on this display (hover expands
    /// what is on screen; an empty region never reacts to the pointer).
    /// `showsNowPlaying` is the per-display toggle for the content: the fixed
    /// window never orders out, so suppression must happen in the view
    /// (SurfaceDisplayPolicy), not at the window level. `showsControls` is the
    /// global view-only toggle (off hides the transport in the expanded view).
    /// `invokeZone` is the click-invoke region — non-nil only while media plays
    /// with nothing visible: a click inside it surfaces the compact appearance;
    /// everything outside it keeps falling through to the menu bar/windows below.
    func apply(frame: CGRect, hoverArmed: Bool, showsNowPlaying: Bool, showsControls: Bool, invokeZone: CGRect?)
    func close()
}
