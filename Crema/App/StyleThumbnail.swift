import AppKit
import SwiftUI

/// A screen with the surface on it. Fixed WIDTH rather than flexible, and the
/// caller's to give: three style tiles plus their spacing have to fit one Settings
/// row, and each display row heads itself with a smaller one. The height is not a
/// taste — it is the described display's own proportions, because a picture whose
/// aspect ratio drifts from the panel it stands for stops being a picture OF
/// anything. The floors and clearances in `Thumbnail` are points, not ratios, so a
/// narrower picture keeps its bar, slit and gap legible instead of scaling them
/// away.
struct StyleThumbnail: View {
    let shapes: StylePreviewShapes
    let wallpaper: NSImage?
    var width: CGFloat = Thumbnail.width

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The user's own desk under a dark wash; why it is theirs, and why it
            // is washed, lives on `TileBackdrop`.
            TileBackdrop(wallpaper: wallpaper)
            menuBar
            slit
            surface
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .accessibilityHidden(true)   // the tile's own words name it
    }

    /// The width, in the proportions of the screen being drawn. A degenerate
    /// geometry reports no ratio at all — zero, the same answer it gives for every
    /// other fraction — and dividing by that hands SwiftUI an infinite frame where
    /// what is wanted is an empty picture, so that one falls back to the shape of
    /// the panel the picker describes by default.
    private var height: CGFloat {
        width / (shapes.aspectRatio > 0 ? shapes.aspectRatio : Thumbnail.referenceAspectRatio)
    }

    /// The strip that makes the picture read as a SCREEN, which is what gives the
    /// surfaces a top edge to be near. Derived height with a floor, because the
    /// derivation alone is invisible: the tile scales its screen by
    /// `width / that screen's width`, so on the reference panel the 32 pt
    /// safe area standing in for the bar arrives as roughly 2.3 pt in a 108 pt
    /// style tile and 1.3 pt in a 60 pt row thumbnail, and the furniture meant to
    /// turn the slit into a bite taken out of the bar does no work at all. The
    /// floor (`Thumbnail.minMenuBar`) is a point value, so it holds at every tile
    /// width; only the derived height moves when a tile is resized.
    private var menuBar: some View {
        ThumbnailMenuBar(
            width: width,
            height: Thumbnail.menuBarHeight(fraction: shapes.menuBar, pictureHeight: height)
        )
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
                    width: slit.width * width,
                    height: max(slit.height * height, Thumbnail.minMenuBar)
                )
                .offset(x: slit.minX * width, y: slit.minY * height)
        }
    }

    /// Rounded on every corner when the surface floats, square on top when it
    /// hangs off the screen edge — which is the difference between the notch skin
    /// and the card at this size. Their gap is well under a point once scaled, so
    /// the silhouette is what carries it, and the silhouette is honest: the notch
    /// surface really is flush with the bezel, continuous with the slit it covers.
    private var surface: some View {
        PreviewSurface(
            size: surfaceSize,
            isOpaque: shapes.surfaceIsOpaque,
            hangsFromTopEdge: shapes.surfaceHangsFromTopEdge,
            arrangement: shapes.contentArrangement
        )
        // Centred on the derived midpoint rather than hung on the derived
        // minX, so the magnification below grows a surface about its own
        // centre — for the unmagnified block the two are the same offset.
        .offset(x: shapes.surface.midX * width - surfaceSize.width / 2, y: surfaceTop)
    }

    /// The drawn surface, in points — the space the content rule answers in, so the
    /// frame above and the rects inside it cannot come from two different sizes.
    ///
    /// The strip skins are magnified: the second sanctioned exaggeration, same
    /// class as the floating clearance below ("only the size of something real").
    /// A 1512 pt screen lands in a 108 pt style tile (a 60 pt row thumbnail is
    /// narrower still), so drawn faithfully the tile's top-edge surfaces are
    /// 13-to-20 pt slivers whose row of cover-and-lines has no room to read — the
    /// field verdict on the faithful cut. The gate is the
    /// content ARRANGEMENT, not the skin's name: it names the thing that needs
    /// width (a row of content), and the near-square block, already legible at
    /// fidelity, stays faithful.
    private var surfaceSize: CGSize {
        let derived = CGSize(width: shapes.surface.width * width, height: shapes.surface.height * height)
        guard shapes.contentArrangement == .coverBesideTwoLines else { return derived }
        return CGSize(
            width: derived.width * Thumbnail.stripSurfaceWidthBoost,
            height: derived.height * Thumbnail.stripSurfaceHeightBoost
        )
    }

    /// The surface's top, with the clearance exaggeration — the magnification's
    /// sibling, over on `surfaceSize`.
    ///
    /// A skin that really clears the menu bar is DRAWN clearing it, by a visible
    /// margin. The card's true clearance is 3 pt on a 982 pt screen — a fifth of a
    /// point once scaled here — so drawn faithfully its edge lands on the same pixel
    /// as the bar's and it reads as welded to the bezel, the opposite of what that
    /// skin does. Only the size of a real gap is exaggerated: a surface that
    /// touches the top edge is still drawn touching it.
    private var surfaceTop: CGFloat {
        let derived = shapes.surface.minY * height
        guard shapes.surfaceClearsTheMenuBar else { return derived }
        return max(derived, Thumbnail.minMenuBar + Thumbnail.floatingClearance)
    }
}
