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
        // Tight, because the ring now needs room outside each picture and three
        // tiles plus their gaps still have to fit the Form row.
        HStack(alignment: .top, spacing: 4) {
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
                // The ring goes OUTSIDE the picture, the way the Appearance and
                // Wallpaper pickers in System Settings do it. Drawn as a border on
                // the thumbnail it would paint inward over the top few points —
                // which is where the whole difference between these skins lives —
                // so selecting a style used to hide the thing being selected.
                StyleThumbnail(shapes: StylePreview.shapes(for: style))
                    .overlay {
                        RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .padding(Thumbnail.ringInset)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: Thumbnail.cornerRadius + Thumbnail.ringInset,
                            style: .continuous
                        )
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
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
        // The picture is hidden from VoiceOver, so without this the whole control
        // is three nouns — exactly the thing this picker exists because names do
        // not convey. Position only, so the words cannot drift from the frame rules
        // the way a description of size or colour would.
        .accessibilityHint(style.previewDescription)
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

    /// The strip that makes the picture read as a SCREEN, which is what gives the
    /// surfaces a top edge to be near. Derived height with a floor, because the
    /// true one is 1.7 pt here and at that size, at 50% white over the desktop, it
    /// was invisible — the furniture that was supposed to turn the slit into a bite
    /// taken out of the bar was doing no work at all.
    private var menuBar: some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: Thumbnail.width, height: max(shapes.menuBar * Thumbnail.height, Thumbnail.minMenuBar))
    }

    @ViewBuilder private var slit: some View {
        if let slit = shapes.slit {
            // Bottom corners only: the slit is cut out of the top edge, so its top
            // corners are the screen's, already rounded by the clip above.
            UnevenRoundedRectangle(bottomLeadingRadius: 1.5, bottomTrailingRadius: 1.5, style: .continuous)
                .fill(.black)
                // Floored with the bar it cuts through: a bite that stops short of
                // the bar's own bottom edge is not a bite, it is a smudge.
                .frame(
                    width: slit.width * Thumbnail.width,
                    height: max(slit.height * Thumbnail.height, Thumbnail.minMenuBar)
                )
                .offset(x: slit.minX * Thumbnail.width, y: slit.minY * Thumbnail.height)
        }
    }

    /// Rounded on every corner when the surface floats, square on top when it
    /// hangs off the screen edge — which is the difference between the notch skin
    /// and the card at this size. Their gap is well under a point once scaled, so
    /// the silhouette is what carries it, and the silhouette is honest: the notch
    /// surface really is flush with the bezel, continuous with the slit it covers.
    private var surface: some View {
        surfaceShape
            .fill(shapes.surfaceIsOpaque ? Color.black : Color.black.opacity(Thumbnail.materialOpacity))
            // Depth only on the ones that float, and it is the cue that survives
            // the scale: the card's real gap from the top edge is under a point
            // here, so a shadow says "on top of the screen" where the gap cannot,
            // and the skin welded to the bezel correctly casts none. Deeper than
            // the surface is translucent, because SwiftUI masks a drop shadow with
            // source alpha and a 0.6 fill would eat nearly half of it.
            .shadow(
                color: .black.opacity(shapes.surfaceIsOpaque ? 0 : 0.8),
                radius: 2.5,
                y: 1.5
            )
            // The real surface's own hairline (vibrantSurface), and the second half
            // of what tells the two top-edge skins apart: the notch is the bezel and
            // has no edge of its own, while a floating panel is outlined against
            // whatever is behind it.
            .overlay {
                if !shapes.surfaceIsOpaque {
                    surfaceShape.strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .overlay { SurfaceContentSketch() }
            .frame(width: shapes.surface.width * Thumbnail.width, height: shapes.surface.height * Thumbnail.height)
            .offset(x: shapes.surface.minX * Thumbnail.width, y: shapes.surface.minY * Thumbnail.height)
    }

    /// One shape for the fill and the hairline, so the outline traces the surface
    /// it outlines. Square on top where the surface hangs off the screen edge,
    /// rounded everywhere it floats.
    private var surfaceShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: shapes.surfaceHangsFromTopEdge ? 0 : 2,
            bottomLeadingRadius: 2,
            bottomTrailingRadius: 2,
            topTrailingRadius: shapes.surfaceHangsFromTopEdge ? 0 : 2,
            style: .continuous
        )
    }
}

/// What the surface is showing, sketched: a square of artwork, the two lines of
/// text beside it, and the scrubber underneath — the expanded now-playing state
/// the preview freezes (StylePreview.previewState).
///
/// Invented, like the menu-bar strip, and for the same reason. These surfaces are
/// 13 to 20 pt wide here, so an empty rectangle reads as a smudge rather than as
/// this app's player, and three smudges read as each other — which is exactly the
/// complaint the pictures came back with from the field. With something inside,
/// the eye finally has proportions to compare, and the two skins that both hug the
/// top edge separate on shape: narrow and tall against wide and flat.
///
/// A sketch and never a rendering. What it has to carry is "a small player, here",
/// which is the whole question this picker asks; drawing the real view would tie
/// the thumbnail to a layout that changes for reasons that have nothing to do with
/// where a skin sits.
private struct SurfaceContentSketch: View {
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let pad = max(size.width * 0.13, 1.2)
            let art = min(size.height * 0.42, size.width * 0.30)
            let line = max(art * 0.2, 0.8)
            VStack(alignment: .leading, spacing: pad * 0.5) {
                HStack(alignment: .top, spacing: pad * 0.6) {
                    RoundedRectangle(cornerRadius: art * 0.18, style: .continuous)
                        .fill(.white.opacity(0.55))
                        .frame(width: art, height: art)
                    VStack(alignment: .leading, spacing: line * 0.8) {
                        Capsule().fill(.white.opacity(0.85)).frame(height: line)
                        // The artist line, shorter than the title above it.
                        Capsule()
                            .fill(.white.opacity(0.45))
                            .frame(width: (size.width - art - pad * 3.6) * 0.62, height: line)
                    }
                }
                Spacer(minLength: 0)
                // The scrubber, filled part-way: a track alone reads as a rule.
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.26))
                    Capsule().fill(.white.opacity(0.9)).frame(width: (size.width - pad * 2) * 0.42)
                }
                .frame(height: max(size.height * 0.055, 0.8))
            }
            .padding(pad)
        }
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
    /// Room between the picture and the selection ring.
    static let ringInset: CGFloat = 3
    /// Floor for the menu-bar strip and the slit that cuts it. Scenery, like the
    /// strip itself: the derived height is 1.7 pt here, which reads as nothing.
    static let minMenuBar: CGFloat = 3.5
    /// How dark a floating surface reads at this size. Hand-calibrated, the one
    /// number here that is taste rather than measurement: the real material is
    /// translucent over whatever is behind it, which a flat thumbnail cannot
    /// reproduce, so this is the value at which the card stops reading as bezel and
    /// still reads as the app's own dark surface.
    static let materialOpacity: Double = 0.6

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
