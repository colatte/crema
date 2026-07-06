import CoreGraphics

/// Which edge of the fixed window the surface is pinned to (how the style
/// draws it): the top-edge skins hang from the top, the classic block sits on
/// its bottom line and grows up.
enum SurfaceVerticalAnchor: Equatable {
    case top, bottom
}

/// Pure click-routing decision for the fixed-size panel: only the visible
/// surface captures the mouse; everywhere else inside the window the click must
/// fall through to whatever sits below (menu bar, status items). `surface` is
/// the current tight rule frame — empty while hidden, so a hidden surface never
/// blocks anything.
enum SurfaceClickThrough {
    static func isInteractive(_ point: CGPoint, surface: CGRect) -> Bool {
        !surface.isEmpty && surface.contains(point)
    }

    /// Screen rect of a surface of `size` as the views draw it: horizontally
    /// centered, pinned to the style's `anchor` edge of the fixed window. Used
    /// with the rendered size the view reports — the rule frame can't know a
    /// width-hugging or view-only-shortened surface.
    static func surfaceRect(size: CGSize, window: CGRect, anchor: SurfaceVerticalAnchor) -> CGRect {
        CGRect(
            x: window.midX - size.width / 2,
            y: anchor == .top ? window.maxY - size.height : window.minY,
            width: size.width,
            height: size.height
        )
    }
}
