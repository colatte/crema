import SwiftUI

extension View {
    /// The Card's floating surface. On macOS 26 and later it is Liquid Glass, the
    /// material the system's own volume and brightness OSD is drawn in, so the
    /// Card reads as the system's: pale over a bright page, dark over a dark one.
    /// Earlier systems have no glass and keep `vibrantSurface`
    /// (docs/DECISIONS.md: the-card-is-glass).
    ///
    /// `dimmed` lays a black layer over the glass, inside the content, wherever
    /// white ink has to read: the player's title and times, and the filled HUD,
    /// whose glyph inverts what lies beneath it and needs a dark remainder. Only
    /// the slider HUD shows the glass bare, as the system's OSD does. It is a
    /// layer and not the glass's own tint, because a black tint lightens the
    /// glass instead (`SurfaceChrome.glassDimOpacity`). The layer's opacity is
    /// animatable, so a HUD↔player morph changes the tone and keeps the material.
    @ViewBuilder
    func cardSurface(in shape: some InsettableShape, dimmed: Bool) -> some View {
        if #available(macOS 26, *) {
            modifier(GlassCardSurface(shape: shape, dimmed: dimmed))
        } else {
            vibrantSurface(in: shape)
        }
    }
}

@available(macOS 26, *)
private struct GlassCardSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let dimmed: Bool

    func body(content: Content) -> some View {
        content
            .background { Color.black.opacity(dimmed ? SurfaceChrome.glassDimOpacity : 0) }
            // Composited and clipped once, as `vibrantSurface` does, and the glass
            // stops `glassInset` inside the outline: the light fill's edge pixels
            // must not show the glass beneath them as a ring.
            .compositingGroup()
            .clipShape(shape)
            .glassEffect(.regular, in: shape.inset(by: SurfaceChrome.glassInset))
            .overlay(shape.strokeBorder(SurfaceChrome.glassRimGradient, lineWidth: SurfaceChrome.glassRimWidth))
    }
}
