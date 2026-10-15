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
    /// The room the Dock keeps along the bottom, left and right edges: the gap
    /// between `frame` and NSScreen's visible frame on that edge, which leaves out
    /// "the area currently occupied by the dock" (Apple docs,
    /// NSScreen.visibleFrame). Zero on an edge without the Dock; a hidden Dock
    /// keeps at most the small strip the system watches to reveal it.
    var dockBottom: CGFloat = 0
    var dockLeft: CGFloat = 0
    var dockRight: CGFloat = 0
}

extension ScreenGeometry {
    /// The Dock's room on the bottom, left and right edges, from a screen's frame
    /// and its visible frame, both in the same global space: each is the gap
    /// between the two rects on that edge, so the screen's origin cancels out. The
    /// top is left out, where the gap is the menu bar's.
    static func dockRoom(frame: CGRect, visible: CGRect) -> (bottom: CGFloat, left: CGFloat, right: CGFloat) {
        (bottom: visible.minY - frame.minY, left: visible.minX - frame.minX, right: frame.maxX - visible.maxX)
    }

    /// The same screen with the Dock's room cleared: what every panel but one
    /// that reads the Dock captures (`PanelSurface.readsTheDock`).
    var withoutDock: ScreenGeometry {
        var geometry = self
        geometry.dockBottom = 0
        geometry.dockLeft = 0
        geometry.dockRight = 0
        return geometry
    }
}
