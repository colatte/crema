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
        // Ten points of air: the field verdict on the 4 pt first cut was one
        // crowded strip. Three tiles plus rings and gaps still fit the ~440 pt
        // Form row with room to spare (3 × 114 + 20 = 362).
        HStack(alignment: .top, spacing: 10) {
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
                // Outside, and here is why for this row: the top few points are where
                // the whole difference between these skins lives, so a border on the
                // thumbnail used to hide the very thing being selected.
                StyleThumbnail(shapes: shapes, wallpaper: wallpaper)
                    .thumbnailSelectionRing(isSelected: isSelected)
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
            // The bar's own bottom edge: over a pale desk the white strip melts
            // into the sky and the slit loses the thing it takes a bite out of.
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.18)).frame(height: 0.5)
            }
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
            // (`SurfaceChrome.tileStrokeTopOpacity`) as a flat line, at the
            // specular's own width. Neither number is written out here: a literal
            // would be a second description of a border the app draws elsewhere,
            // in the one place a user compares the skins. Only the notch has none —
            // it camouflages with the cutout it covers, and that is the difference
            // a user names first when the three are side by side.
            .overlay {
                if !shapes.surfaceIsOpaque {
                    surfaceShape.strokeBorder(
                        .white.opacity(SurfaceChrome.tileStrokeTopOpacity),
                        lineWidth: SurfaceChrome.specularWidth
                    )
                }
            }
            .frame(width: surfaceSize.width, height: surfaceSize.height)
            // Centred on the derived midpoint rather than hung on the derived
            // minX, so the magnification below grows a surface about its own
            // centre — for the unmagnified block the two are the same offset.
            .offset(x: shapes.surface.midX * Thumbnail.width - surfaceSize.width / 2, y: surfaceTop)
    }

    /// The drawn surface, in points — the space the content rule answers in, so the
    /// frame above and the rects inside it cannot come from two different sizes.
    ///
    /// The strip skins are magnified: the second sanctioned exaggeration, same
    /// class as the floating clearance below ("only the size of something real").
    /// A 1512 pt screen lands in a 108 pt picture, so drawn faithfully the
    /// top-edge surfaces are 13-to-20 pt slivers whose row of cover-and-lines has
    /// no room to read — the field verdict on the faithful cut. The gate is the
    /// content ARRANGEMENT, not the skin's name: it names the thing that needs
    /// width (a row of content), and the near-square block, already legible at
    /// fidelity, stays faithful.
    private var surfaceSize: CGSize {
        let derived = CGSize(width: shapes.surface.width * Thumbnail.width, height: shapes.surface.height * height)
        guard shapes.contentArrangement == .coverBesideTwoLines else { return derived }
        return CGSize(
            width: derived.width * Thumbnail.stripSurfaceWidthBoost,
            height: derived.height * Thumbnail.stripSurfaceHeightBoost
        )
    }

    /// What the surface holds, in miniature: cover art and the track's lines.
    ///
    /// Placed by the shared rule (`StylePreviewContent`) rather than by eye — the
    /// notch tile draws its surface at some 26 by 15 pt even magnified, where
    /// "looks right" is not a check anyone can repeat — and drawn only when that
    /// rule finds room: silhouette alone says less than furniture too small to
    /// read says wrong.
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

    /// The surface's top, with the clearance exaggeration — the magnification's
    /// sibling, over on `surfaceSize`.
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
