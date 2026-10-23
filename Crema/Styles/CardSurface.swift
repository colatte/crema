import SwiftUI

extension View {
    /// The Card's floating surface. On macOS 26 and later it is Liquid Glass, the
    /// material the system's own volume and brightness OSD is drawn in, so the
    /// Card reads as the system's, with the system's rim drawn by hand because a
    /// never-key panel's glass draws none. The glass is `.clear`,
    /// whose body matches the system's on both kinds of page. Bare, it turns pale
    /// over a bright page, which the indicator accepts as the system's OSD does;
    /// a surface that `carriesText` is dimmed so its white text meets the
    /// minimum (`SurfaceChrome.glassDimming`). Systems before macOS 26 have no
    /// glass and keep `vibrantSurface`, dark under both (docs/DECISIONS.md:
    /// the-card-is-glass, where the measurements are).
    @ViewBuilder
    func cardSurface(in shape: some InsettableShape, carriesText: Bool) -> some View {
        if #available(macOS 26, *) {
            modifier(GlassCardSurface(shape: shape, carriesText: carriesText))
        } else {
            vibrantSurface(in: shape)
        }
    }
}

@available(macOS 26, *)
private struct GlassCardSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let carriesText: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        // What draws on the glass reads it: a recess tuned for a dark surface
        // would cut a groove into a pale one (CapsuleTrack). The dimming sits
        // under the content and over the glass, so the glass still blurs what
        // is behind it.
        content
            .environment(\.surfaceIsGlass, true)
            .background { Color.black.opacity(SurfaceChrome.glassDimming(contrast, carriesText: carriesText)) }
            // Composited and clipped once, as `vibrantSurface` does: the light
            // fill's edge pixels must not show the glass beneath them as a ring.
            // Clipped where the glass is, so the two share one edge.
            .compositingGroup()
            .clipShape(shape.inset(by: SurfaceChrome.glassEdgeCut))
            // The glass to the outline, its own darker outermost pixel cut away
            // (`SurfaceChrome.glassEdgeCut`). No shadow: the system's OSD casts
            // none.
            .background {
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .clipShape(shape.inset(by: SurfaceChrome.glassEdgeCut))
            }
            .overlay {
                let rim = SurfaceChrome.glassRim(carriesText: carriesText)
                ZStack {
                    ForEach(rim.indices, id: \.self) { index in
                        shape.strokeBorder(SurfaceChrome.glassRimGradient(rim[index]), lineWidth: rim[index].width)
                    }
                }
            }
    }
}

private struct SurfaceIsGlassKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the surface underneath is the Card's Liquid Glass, which follows
    /// the page behind it instead of staying dark (`cardSurface`).
    var surfaceIsGlass: Bool {
        get { self[SurfaceIsGlassKey.self] }
        set { self[SurfaceIsGlassKey.self] = newValue }
    }
}
