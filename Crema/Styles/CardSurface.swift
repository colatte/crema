import SwiftUI

extension View {
    /// The Card's floating surface. On macOS 26 and later it is Liquid Glass, the
    /// material the system's own volume and brightness OSD is drawn in, so the
    /// Card reads as the system's: pale over a bright page, dark over a dark one,
    /// with the system's rim and shadow drawn by hand because a never-key panel's
    /// glass draws neither. Earlier systems have no glass and keep
    /// `vibrantSurface` (docs/DECISIONS.md: the-card-is-glass).
    @ViewBuilder
    func cardSurface(in shape: some InsettableShape) -> some View {
        if #available(macOS 26, *) {
            modifier(GlassCardSurface(shape: shape))
        } else {
            vibrantSurface(in: shape)
        }
    }
}

@available(macOS 26, *)
private struct GlassCardSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // Increase Contrast dims the glass so white ink meets the minimum, the
        // higher contrast scheme the HIG asks that setting to deliver.
        content
            .background { Color.black.opacity(SurfaceChrome.glassDimming(contrast)) }
            // Composited and clipped once, as `vibrantSurface` does, and the glass
            // stops `glassInset` inside the outline: the light fill's edge pixels
            // must not show the glass beneath them as a ring.
            .compositingGroup()
            .clipShape(shape)
            .glassEffect(.regular, in: shape.inset(by: SurfaceChrome.glassInset))
            // The rim, glow under edge: the glow falls off inward from the outline
            // and the edge line closes the gap the inset leaves.
            .overlay {
                ZStack {
                    shape.strokeBorder(SurfaceChrome.glassGlowGradient, lineWidth: SurfaceChrome.glassGlowWidth)
                    shape.strokeBorder(SurfaceChrome.glassRimGradient, lineWidth: SurfaceChrome.glassRimWidth)
                }
            }
            .shadow(
                color: .black.opacity(SurfaceChrome.glassShadowOpacity),
                radius: SurfaceChrome.glassShadowRadius,
                y: SurfaceChrome.glassShadowY
            )
    }
}
