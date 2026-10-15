import SwiftUI

/// A skin's surface in miniature: its shape filled dark, its depth, its border and
/// what it holds. One drawing for every Settings picture that shows a surface — the
/// style tiles and the placement map's card — so a surface cannot come to look
/// different from one picture to the next.
struct PreviewSurface: View {
    let size: CGSize
    let isOpaque: Bool
    let hangsFromTopEdge: Bool
    let arrangement: PreviewContentArrangement
    /// The corner of a floating surface. The style tiles round every skin alike;
    /// the placement map derives the card's from the real one, beside a HUD bar
    /// that is rounded the way the real bar is.
    var cornerRadius: CGFloat = 2

    var body: some View {
        shape
            .fill(isOpaque ? Color.black : Color.black.opacity(Thumbnail.floatingSurfaceOpacity))
            // Depth only on the ones that float, and it is the cue that survives
            // the scale: the card's real gap from the top edge is under a point
            // here, so a shadow says "on top of the screen" where the gap cannot,
            // and the skin welded to the bezel correctly casts none.
            .previewDepth(floats: !hangsFromTopEdge)
            .overlay { content }
            // The floating skins' own border (vibrantSurface), read from the one
            // place its numbers live: the real surface ramps a specular from the
            // top edge, and at this size a hairline that fades reads as no edge at
            // all, so the picture takes that ramp's brightest point
            // (`SurfaceChrome.tileStrokeTopOpacity`) as a flat line, at the
            // specular's own width. Neither number is written out here: a literal
            // would be a second description of a border the app draws elsewhere,
            // in the one place a user compares the skins. Only the notch has none —
            // it camouflages with the cutout it covers, and that is the difference
            // a user names first when the three are side by side.
            .overlay {
                if !isOpaque {
                    shape.strokeBorder(
                        .white.opacity(SurfaceChrome.tileStrokeTopOpacity),
                        lineWidth: SurfaceChrome.specularWidth
                    )
                }
            }
            .frame(width: size.width, height: size.height)
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

extension View {
    /// The depth a floating surface casts in the Settings pictures; none for one
    /// welded to the screen's edge. One recipe for every surface those pictures
    /// draw, so the card and the HUD bar beside it cannot drift apart.
    func previewDepth(floats: Bool) -> some View {
        shadow(color: .black.opacity(floats ? 0.75 : 0), radius: 2.5, y: 1.5)
    }
}
