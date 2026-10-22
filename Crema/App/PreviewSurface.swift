import SwiftUI

/// A skin's surface in miniature: its shape filled dark, its depth, its edge and
/// what it holds. One drawing for every style tile, so no skin's miniature can come
/// to look different from another's in anything but the skin itself.
struct PreviewSurface: View {
    let size: CGSize
    let isOpaque: Bool
    let isGlass: Bool
    let hangsFromTopEdge: Bool
    let arrangement: PreviewContentArrangement
    /// The corner of a floating surface: the pictures round every skin alike.
    private let cornerRadius: CGFloat = 2

    var body: some View {
        // Depth only on the ones that float, and it is the cue that survives the
        // scale: the card's real gap from the top edge is under a point here, so
        // a shadow says "on top of the screen" where the gap cannot, and the skin
        // welded to the bezel correctly casts none.
        material
            .previewDepth(floats: !hangsFromTopEdge)
            .overlay { content }
            // The film path's own border (vibrantSurface), read from the one
            // place its numbers live: the real surface ramps a specular from the
            // top edge, and at this size a hairline that fades reads as no edge at
            // all, so the picture takes that ramp's brightest point
            // (`SurfaceChrome.tileStrokeTopOpacity`) as a flat line, at the
            // specular's own width. Neither number is written out here: a literal
            // would be a second description of a border the app draws elsewhere,
            // in the one place a user compares the skins. The notch has none — it
            // camouflages with the cutout it covers, and that is the difference a
            // user names first when the three are side by side — and the glass
            // draws its own.
            .overlay {
                if !isOpaque, !isGlass {
                    shape.strokeBorder(
                        .white.opacity(SurfaceChrome.tileStrokeTopOpacity),
                        lineWidth: SurfaceChrome.specularWidth
                    )
                }
            }
            .frame(width: size.width, height: size.height)
    }

    /// The Card's glass as glass: the Settings window is the key window, where
    /// glass draws its own rim and refracts the desk drawn under the picture, so
    /// it needs no stand-in and no hairline. The other floating skins keep the
    /// dark stand-in for a material that cannot be drawn here (it blends what is
    /// behind the window, not the desk in the picture).
    @ViewBuilder private var material: some View {
        if isGlass, #available(macOS 26, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            shape.fill(isOpaque ? Color.black : Color.black.opacity(Thumbnail.floatingSurfaceOpacity))
        }
    }

    /// What the surface holds, in miniature: cover art and the track's lines.
    ///
    /// Placed by the shared rule (`StylePreviewContent`) rather than by eye — the
    /// notch tile draws its surface at some 26 by 15 pt even magnified, where
    /// "looks right" is not a check anyone can repeat — and drawn only when that
    /// rule finds room: silhouette alone says less than furniture too small to
    /// read says wrong.
    @ViewBuilder private var content: some View {
        if let layout = StylePreviewContent.layout(in: CGRect(origin: .zero, size: size), arrangement: arrangement) {
            ZStack(alignment: .topLeading) {
                // Takes the whole proposal, so everything below is offset from the
                // surface's own top-leading corner — the origin the rule measured
                // from. Without it the stack would shrink to its contents and the
                // rects would land wherever that left them.
                Color.clear
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Self.cover)
                    .frame(width: layout.cover.width, height: layout.cover.height)
                    .offset(x: layout.cover.minX, y: layout.cover.minY)
                // Title first, artist under it, and the second one dimmer: at this
                // size the hierarchy is the only thing a line can say.
                ForEach(Array(layout.titleLines.enumerated()), id: \.offset) { line in
                    Capsule()
                        .fill(.white.opacity(line.offset == 0 ? 0.45 : 0.3))
                        .frame(width: line.element.width, height: line.element.height)
                        .offset(x: line.element.minX, y: line.element.minY)
                }
            }
        }
    }

    /// A stand-in for cover art: two colours, because one flat square reads as a
    /// hole in the surface rather than a picture in it.
    private static let cover = LinearGradient(
        colors: [Color(red: 0.60, green: 0.47, blue: 0.40), Color(red: 0.27, green: 0.30, blue: 0.44)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// One shape for the fill and the hairline, so the outline traces the surface
    /// it outlines. Square on top where the surface hangs off the screen edge,
    /// rounded everywhere it floats.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: hangsFromTopEdge ? 0 : cornerRadius,
            bottomLeadingRadius: cornerRadius,
            bottomTrailingRadius: cornerRadius,
            topTrailingRadius: hangsFromTopEdge ? 0 : cornerRadius,
            style: .continuous
        )
    }
}

private extension View {
    /// The depth a floating surface casts in a style tile; none for one welded to
    /// the screen's edge.
    func previewDepth(floats: Bool) -> some View {
        shadow(color: .black.opacity(floats ? 0.75 : 0), radius: 2.5, y: 1.5)
    }
}
