import SwiftUI

/// Pick the skin by looking at it.
///
/// Three thumbnails instead of three nouns, the way System Settings lets you
/// choose an appearance from pictures. "Notch", "Card" and "Classic" are names for
/// something the person has not seen yet, so the words are exactly the part a
/// first-time user cannot evaluate — and this app's whole surface is a shape in a
/// place, which is a thing a picture says in full.
///
/// Every rectangle is computed from the skin's own frame rule (`StylePreview`), so
/// a change that moves a surface moves its thumbnail with it.
struct StylePicker: View {
    @Binding var selection: Style

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Style.allCases, id: \.self) { style in
                StyleTile(style: style, isSelected: style == selection) { selection = style }
            }
        }
        // One control, three options: without this the three buttons are read out
        // as unrelated, and the Style label above never reaches them.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.general.style", defaultValue: "Style"))
    }
}

/// One option: the picture, its name, and the selection ring.
private struct StyleTile: View {
    let style: Style
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                StyleThumbnail(shapes: StylePreview.shapes(for: style))
                    .overlay {
                        RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous)
                            .strokeBorder(
                                isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                lineWidth: isSelected ? 2.5 : 1
                            )
                    }
                Text(style.displayName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        // Plain, because the tile IS the control: a bordered button would draw a
        // second frame around a picture that already has one.
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// A screen with the surface on it. Fixed size rather than flexible: three of
/// these plus their spacing have to fit the Settings window, and a picture whose
/// aspect ratio drifts from a real panel stops being a picture OF anything.
private struct StyleThumbnail: View {
    let shapes: StylePreviewShapes

    var body: some View {
        ZStack(alignment: .topLeading) {
            Thumbnail.desktop
            menuBar
            slit
            surface
        }
        .frame(width: Thumbnail.width, height: Thumbnail.height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .accessibilityHidden(true)   // the tile's own label names it
    }

    private var menuBar: some View {
        Rectangle()
            .fill(.white.opacity(0.5))
            .frame(width: Thumbnail.width, height: shapes.menuBar * Thumbnail.height)
    }

    @ViewBuilder private var slit: some View {
        if let slit = shapes.slit {
            // Bottom corners only: the slit is cut out of the top edge, so its top
            // corners are the screen's, already rounded by the clip above.
            UnevenRoundedRectangle(bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5, style: .continuous)
                .fill(.black)
                .frame(width: slit.width * Thumbnail.width, height: slit.height * Thumbnail.height)
                .offset(x: slit.minX * Thumbnail.width, y: slit.minY * Thumbnail.height)
        }
    }

    /// Rounded on every corner when the surface floats, square on top when it
    /// hangs off the screen edge — which is the difference between the notch skin
    /// and the card at this size. Their gap is well under a point once scaled, so
    /// the silhouette is what carries it, and the silhouette is honest: the notch
    /// surface really is flush with the bezel, continuous with the slit it covers.
    private var surface: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: shapes.surfaceHangsFromTopEdge ? 0 : 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 2,
            topTrailingRadius: shapes.surfaceHangsFromTopEdge ? 0 : 2,
            style: .continuous
        )
        .fill(.black)
        // Depth only on the ones that float. It is the cue that survives the scale:
        // the card sits less than a point below the top edge here, so a shadow says
        // "on top of the screen" where the gap cannot, and the skin welded to the
        // bezel correctly casts none.
        .shadow(
            color: .black.opacity(shapes.surfaceHangsFromTopEdge ? 0 : 0.5),
            radius: 2.5,
            y: 1.5
        )
        .frame(width: shapes.surface.width * Thumbnail.width, height: shapes.surface.height * Thumbnail.height)
        .offset(x: shapes.surface.minX * Thumbnail.width, y: shapes.surface.minY * Thumbnail.height)
    }
}

/// Drawing constants shared by the tile and its picture, so the selection ring
/// traces the same rounded rect the screen is clipped to.
private enum Thumbnail {
    /// Sized to the row it sits in, not to taste: three of these plus their gaps
    /// and the "Style" label have to fit the 500 pt Settings window, whose grouped
    /// Form row is about 440 pt wide. 128 pt tiles overflowed it.
    static let width: CGFloat = 108
    /// The reference panel's own aspect ratio, so the picture is shaped like the
    /// Mac it describes.
    static let height: CGFloat = width * 982 / 1512
    static let cornerRadius: CGFloat = 6

    /// A desktop to put the surface on. Deliberately flat and dim: the subject is
    /// the black shape, and a busy wallpaper would compete with the one thing
    /// these pictures exist to compare. Fixed rather than theme-following for the
    /// same reason a photo of a screen does not change with the room — and because
    /// the app's surfaces are always dark, so a light thumbnail would misdescribe
    /// them (docs/DECISIONS.md: hud-fixed-dark-palette).
    static let desktop = LinearGradient(
        colors: [Color(red: 0.29, green: 0.33, blue: 0.42), Color(red: 0.17, green: 0.19, blue: 0.25)],
        startPoint: .top,
        endPoint: .bottom
    )
}
