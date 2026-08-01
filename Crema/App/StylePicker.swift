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
///
/// This control speaks for EVERY display, and only for that: no screen's geometry
/// decides which tiles are offerable, because the choice is not about one screen —
/// some connected display may well honour it, and where none does the footer
/// beside it says so in a sentence rather than greying out the option the app
/// ships declaring. One display's own style is a different control in a different
/// place (the per-display popup in the Displays section), and asking this one to
/// be both is what made a tile mean two things at once.
struct StylePicker: View {
    @Binding var selection: Style

    var body: some View {
        // Tight, because the ring needs room outside each picture and three
        // tiles plus their gaps still have to fit the Form row.
        HStack(alignment: .top, spacing: 4) {
            ForEach(Style.allCases, id: \.self) { style in
                // Asking for the shapes without naming a panel is deliberately not
                // the same as passing the canonical one: the default belongs to
                // `StylePreview`, so this picker keeps asking about whatever panel
                // that file decides is the one to teach from, rather than pinning a
                // second copy of the answer here.
                StyleTile(
                    style: style,
                    shapes: StylePreview.shapes(for: style),
                    isSelected: style == selection
                ) { selection = style }
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
    let shapes: StylePreviewShapes
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
                StyleThumbnail(shapes: shapes)
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

/// A screen with the surface on it. Fixed WIDTH rather than flexible: three of
/// these plus their spacing have to fit the Settings window. The height is not a
/// taste — it is the described display's own proportions, because a picture whose
/// aspect ratio drifts from the panel it stands for stops being a picture OF
/// anything.
private struct StyleThumbnail: View {
    let shapes: StylePreviewShapes

    var body: some View {
        ZStack(alignment: .topLeading) {
            Thumbnail.desktop
            menuBar
            slit
            surface
        }
        .frame(width: Thumbnail.width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .accessibilityHidden(true)   // the tile's own label names it
    }

    /// The width, in the proportions of the screen being drawn. A degenerate
    /// geometry reports no ratio at all — zero, the same answer it gives for every
    /// other fraction — and dividing by that hands SwiftUI an infinite frame where
    /// what is wanted is an empty picture, so that one falls back to the shape of
    /// the panel the picker describes by default.
    private var height: CGFloat {
        Thumbnail.width / (shapes.aspectRatio > 0 ? shapes.aspectRatio : Thumbnail.referenceAspectRatio)
    }

    /// The strip that makes the picture read as a SCREEN, which is what gives the
    /// surfaces a top edge to be near. Derived height with a floor, because the
    /// derivation alone is invisible: the tile scales its screen by
    /// `Thumbnail.width / that screen's width`, so on the reference panel the 32 pt
    /// safe area standing in for the bar arrives as roughly 2.3 pt, and the
    /// furniture meant to turn the slit into a bite taken out of the bar does no
    /// work at all. The ratio is what to re-check when the tile is resized; the
    /// point value follows from it.
    private var menuBar: some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: Thumbnail.width, height: max(shapes.menuBar * height, Thumbnail.minMenuBar))
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
                    height: max(slit.height * height, Thumbnail.minMenuBar)
                )
                .offset(x: slit.minX * Thumbnail.width, y: slit.minY * height)
        }
    }

    /// Rounded on every corner when the surface floats, square on top when it
    /// hangs off the screen edge — which is the difference between the notch skin
    /// and the card at this size. Their gap is well under a point once scaled, so
    /// the silhouette is what carries it, and the silhouette is honest: the notch
    /// surface really is flush with the bezel, continuous with the slit it covers.
    private var surface: some View {
        surfaceShape
            .fill(shapes.surfaceIsOpaque ? Color.black : Color.black.opacity(0.62))
            // Depth only on the ones that float, and it is the cue that survives
            // the scale: the card's real gap from the top edge is under a point
            // here, so a shadow says "on top of the screen" where the gap cannot,
            // and the skin welded to the bezel correctly casts none.
            .shadow(
                color: .black.opacity(shapes.surfaceHangsFromTopEdge ? 0 : 0.75),
                radius: 2.5,
                y: 1.5
            )
            // The floating skins' own hairline (vibrantSurface). Only the notch is
            // solid black — it camouflages with the cutout it covers — and that is
            // the difference a user names first when the three are side by side.
            .overlay {
                if !shapes.surfaceIsOpaque {
                    surfaceShape.strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
            }
            .frame(width: shapes.surface.width * Thumbnail.width, height: shapes.surface.height * height)
            .offset(x: shapes.surface.minX * Thumbnail.width, y: surfaceTop)
    }

    /// The surface's top, with the one exaggeration in the picture.
    ///
    /// A skin that really clears the menu bar is DRAWN clearing it, by a visible
    /// margin. The card's true clearance is 3 pt on a 982 pt screen — a fifth of a
    /// point once scaled here — so drawn faithfully its edge lands on the same pixel
    /// as the bar's and it reads as welded to the bezel, which is the opposite of
    /// what that skin does and the complaint these pictures came back with twice.
    /// Only the size of a real gap is exaggerated: a surface that touches the top
    /// edge is still drawn touching it.
    private var surfaceTop: CGFloat {
        let derived = shapes.surface.minY * height
        guard shapes.surfaceClearsTheMenuBar else { return derived }
        return max(derived, Thumbnail.minMenuBar + Thumbnail.floatingClearance)
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

/// Drawing constants shared by the tile and its picture, so the selection ring
/// traces the same rounded rect the screen is clipped to.
private enum Thumbnail {
    /// Sized to the row it sits in, not to taste: three of these plus their gaps
    /// and the "Style" label have to fit the 500 pt Settings window, whose grouped
    /// Form row is about 440 pt wide. 128 pt tiles overflowed it.
    static let width: CGFloat = 108
    /// The shape of the panel the preview describes when no display is named, and
    /// the stand-in for a screen that reports none. Read off that same measured
    /// geometry rather than restated, so the two cannot come to disagree about
    /// what a tile is shaped like.
    static let referenceAspectRatio = StylePreview.notchedReference.frame.width / StylePreview.notchedReference.frame.height
    static let cornerRadius: CGFloat = 6
    /// Room between the picture and the selection ring.
    static let ringInset: CGFloat = 3
    /// Floor for the menu-bar strip and the slit that cuts it. Scenery, like the
    /// strip itself: the tile scales its screen by `width / that screen's width`,
    /// so the reference panel's 32 pt safe area derives to roughly 2.3 pt here,
    /// which reads as nothing. A point value rather than a ratio because what it
    /// defends is legibility on screen — resize the tile and the derived height
    /// moves, this floor does not.
    static let minMenuBar: CGFloat = 3.5
    /// How far below the drawn menu bar a floating surface sits. Enough to be a gap
    /// and not a seam; the true one is a fifth of a point at this size.
    static let floatingClearance: CGFloat = 2.5

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
