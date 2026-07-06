import CoreGraphics

/// Pure description of one screen — everything a frame rule needs, and no
/// AppKit. Built at the border (ScreenTranslation) from NSScreen; on screens
/// without a notch, safeTop/aux stay zero.
/// Coordinates are AppKit screen coordinates (origin at bottom-left, y up).
struct ScreenGeometry: Equatable, Sendable {
    /// Full screen frame in global screen coordinates.
    var frame: CGRect
    /// Height of the top safe area (the notch slit); 0 without a notch.
    var safeTop: CGFloat = 0
    /// Width of the auxiliary area left of the notch; 0 without a notch.
    var auxLeft: CGFloat = 0
    /// Width of the auxiliary area right of the notch; 0 without a notch.
    var auxRight: CGFloat = 0
    /// Backing scale (device pixels per point): frame rules snap pixel-critical
    /// edges with it. Defaults to 2 — every modern Mac panel.
    var scale: CGFloat = 2
}
