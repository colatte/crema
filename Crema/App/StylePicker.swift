import AppKit
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
    /// The desk the tiles stand on, handed in rather than read here: a view that
    /// asked the system for the desktop picture would ask again on every body,
    /// where the picture is worth exactly one decode per window opening
    /// (`WallpaperTileStore`). Nil is a complete answer and not a missing one — the
    /// tiles draw their own desk — so a caller with no scenery to give leaves it
    /// out.
    var wallpaper: NSImage?

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
                    wallpaper: wallpaper,
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

/// One option: the picture, its name and caption, and the selection ring.
private struct StyleTile: View {
    let style: Style
    let shapes: StylePreviewShapes
    let wallpaper: NSImage?
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
                StyleThumbnail(shapes: shapes, wallpaper: wallpaper)
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
                // Tighter than the gap above: the caption belongs to the name, not
                // to the picture, and equal spacing would leave it floating between
                // two tiles' worth of words.
                VStack(spacing: 1) {
                    Text(style.displayName)
                        .font(.callout)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Text(style.previewDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        // Held to the picture's width and allowed to wrap: three
                        // tiles have to fit one Form row, so a caption free to grow
                        // sideways would widen the row instead of taking a second
                        // line — and a sentence cut short by an ellipsis says the
                        // position wrong rather than not at all.
                        .frame(width: Thumbnail.width)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Plain, because the tile IS the control: a bordered button would draw a
        // second frame around a picture that already has one.
        .buttonStyle(.plain)
        .contentShape(.rect)
        // No hand-written label here: the button composes one from the two texts it
        // draws — the name, then the sentence under it — so VoiceOver says exactly
        // what the eye reads, once. Naming the style instead would replace both and
        // leave the control as the three nouns the pictures exist because names do
        // not convey; a hint carrying the same sentence would say it a second time.
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
    let wallpaper: NSImage?

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The user's own desk under a dark wash; why it is theirs, and why it
            // is washed, lives on `TileBackdrop`.
            TileBackdrop(wallpaper: wallpaper)
            menuBar
            slit
            surface
        }
        .frame(width: Thumbnail.width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .accessibilityHidden(true)   // the tile's own words name it
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
            .overlay { content }
            // The floating skins' own border (vibrantSurface), read from the one
            // place its numbers live: the real surface ramps a specular from the
            // top edge, and at this size a hairline that fades reads as no edge at
            // all, so the picture takes that ramp's brightest point
            // (`SurfaceChrome.tileStrokeTopOpacity`) as a flat line. A literal here
            // would be a second description of a border the app draws elsewhere,
            // in the one place a user compares the skins. Only the notch has none —
            // it camouflages with the cutout it covers, and that is the difference
            // a user names first when the three are side by side.
            .overlay {
                if !shapes.surfaceIsOpaque {
                    surfaceShape.strokeBorder(.white.opacity(SurfaceChrome.tileStrokeTopOpacity), lineWidth: 0.5)
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            .offset(x: shapes.surface.minX * Thumbnail.width, y: surfaceTop)
    }

    /// The drawn surface, in points — the space the content rule answers in, so the
    /// frame above and the rects inside it cannot come from two different sizes.
    private var surfaceSize: CGSize {
        CGSize(width: shapes.surface.width * Thumbnail.width, height: shapes.surface.height * height)
    }

    /// What the surface holds, in miniature: cover art and the track's lines.
    ///
    /// Placed by the shared rule (`StylePreviewContent`) rather than by eye — the
    /// notch tile draws its surface at some 13 by 11 pt, where "looks right" is not
    /// a check anyone can repeat — and drawn only when that rule finds room:
    /// silhouette alone says less than furniture too small to read says wrong.
    @ViewBuilder private var content: some View {
        if let layout = StylePreviewContent.layout(
            in: CGRect(origin: .zero, size: surfaceSize),
            arrangement: shapes.contentArrangement
        ) {
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
/// traces the same rounded rect the screen is clipped to. Not private because the
/// indicator mini-tiles under this row take the same corner radius and ring inset:
/// two rows of pictures in one Settings section have to wear one frame, and a
/// second copy of these numbers is how they would come to wear two.
enum Thumbnail {
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
}
