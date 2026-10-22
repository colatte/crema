import SwiftUI

extension View {
    /// The Card's floating surface. On macOS 26 and later it is Liquid Glass, the
    /// material the system's own volume and brightness OSD is drawn in, so the
    /// Card reads as the system's: pale over a bright page, dark over a dark one,
    /// with the system's rim and shadow drawn by hand because a never-key panel's
    /// glass draws neither. The glass is `.clear`, whose body matches the
    /// system's on both kinds of page (`SurfaceChrome.glassRim`). Earlier systems have no glass and keep
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
            // Composited and clipped once, as `vibrantSurface` does: the light
            // fill's edge pixels must not show the glass beneath them as a ring.
            .compositingGroup()
            .clipShape(shape)
            // The glass as a layer of its own, so its edge can be cut: it stops
            // `glassInset` inside the outline, and the ring its own edge draws,
            // darker than its body over a pale page, is clipped a further
            // `glassEdgeCut` away. The rim covers the band that leaves.
            .background {
                Color.clear
                    .glassEffect(.clear, in: shape.inset(by: SurfaceChrome.glassInset))
                    .clipShape(shape.inset(by: SurfaceChrome.glassInset + SurfaceChrome.glassEdgeCut))
            }
            .overlay {
                ZStack {
                    ForEach(SurfaceChrome.glassRim.indices, id: \.self) { index in
                        let stroke = SurfaceChrome.glassRim[index]
                        shape.strokeBorder(SurfaceChrome.glassRimGradient(stroke), lineWidth: stroke.width)
                    }
                }
            }
            .shadow(
                color: .black.opacity(SurfaceChrome.glassShadowOpacity),
                radius: SurfaceChrome.glassShadowRadius,
                y: SurfaceChrome.glassShadowY
            )
    }
}
