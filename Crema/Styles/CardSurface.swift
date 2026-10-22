import SwiftUI

extension View {
    /// The Card's floating surface. On macOS 26 and later it is Liquid Glass, the
    /// material the system's own volume and brightness OSD is drawn in, so the
    /// Card reads as the system's, with the system's rim and shadow drawn by hand
    /// because a never-key panel's glass draws neither. The glass is `.clear`,
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
            .compositingGroup()
            .clipShape(shape)
            // The glass as a layer of its own, so its edge can be cut: under the
            // indicator it stops `glassInset` inside the outline, and the ring its
            // own edge draws, darker than its body over a pale page, is clipped a
            // further `glassEdgeCut` away, the rim covering the band that leaves;
            // under the player it reaches the outline (`glassStop`).
            .background {
                let stop = SurfaceChrome.glassStop(carriesText: carriesText)
                Color.clear
                    .glassEffect(.clear, in: shape.inset(by: stop.inset))
                    .clipShape(shape.inset(by: stop.inset + stop.cut))
            }
            .overlay {
                let rim = SurfaceChrome.glassRim(carriesText: carriesText)
                ZStack {
                    ForEach(rim.indices, id: \.self) { index in
                        shape.strokeBorder(SurfaceChrome.glassRimGradient(rim[index]), lineWidth: rim[index].width)
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
