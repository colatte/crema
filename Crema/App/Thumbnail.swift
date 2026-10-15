import SwiftUI

/// The frame every Settings picture wears — the numbers AND the ring drawn from
/// them.
///
/// It lives in a file of its own because it belongs to no one picture: the style
/// tiles, the indicator mini-tiles and the thumbnail heading each display row sit
/// in one Settings pane and have to look like one family, so a second copy of
/// these numbers is how they would come to wear two frames. Sharing the constants
/// alone is not enough: with each picture tracing its own ring, the numbers cannot
/// diverge but the lines drawing them can.
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
    /// The gap between the small tiles of the Card's rows — the indicator
    /// close-ups and the placement screens — tighter than the style tiles' row.
    static let smallTileSpacing: CGFloat = 4
    /// Room between the picture and the selection ring.
    fileprivate static let ringInset: CGFloat = 3
    /// Floor for the menu-bar strip and the slit that cuts it. Scenery, like the
    /// strip itself: the tile scales its screen by `width / that screen's width`,
    /// so the reference panel's 32 pt safe area derives to roughly 2.3 pt at the
    /// style tile's `width` and 1.3 pt in a 60 pt display-row thumbnail, which
    /// reads as nothing. A point value rather than a ratio because what it defends
    /// is legibility on screen — resize the tile and the derived height moves,
    /// this floor does not.
    static let minMenuBar: CGFloat = 3.5
    /// How far below the drawn menu bar a floating surface sits. Enough to be a gap
    /// and not a seam; the true one is a fifth of a point at this size.
    static let floatingClearance: CGFloat = 2.5
    /// How much wider than faithful the strip surfaces are drawn, and how much
    /// taller. Calibrated against the drawing the owner approved (surfaces at
    /// roughly 28-37% of the tile's width, cover at ~45% of their height), not
    /// to taste; the rationale for exaggerating at all is on `surfaceSize`.
    static let stripSurfaceWidthBoost: CGFloat = 2.0
    static let stripSurfaceHeightBoost: CGFloat = 1.35
    /// How dark every picture draws a floating surface: it stands in for a material
    /// that cannot be drawn in Settings, dark enough that the surface on the desk
    /// reads as the app's (docs/DECISIONS.md: hud-fixed-dark-palette).
    static let floatingSurfaceOpacity = 0.62

    /// The menu bar strip's height in a picture `pictureHeight` tall, from its
    /// fraction of the screen, floored at `minMenuBar`.
    static func menuBarHeight(fraction: CGFloat, pictureHeight: CGFloat) -> CGFloat {
        max(fraction * pictureHeight, minMenuBar)
    }
}

/// The strip that makes a picture read as a SCREEN, which is what gives the
/// surfaces in it a top edge to be near. One drawing for every picture of a
/// screen in Settings, so they cannot come to wear two menu bars.
struct ThumbnailMenuBar: View {
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.85))
            .frame(width: width, height: height)
            // The bar's own bottom edge: over a pale desk the white strip melts
            // into the sky and the slit loses the thing it takes a bite out of.
            .overlay(alignment: .bottom) {
                Rectangle().fill(.black.opacity(0.18)).frame(height: 0.5)
            }
    }
}

extension View {
    /// A hairline tracing the picture, then the selection ring OUTSIDE it, the
    /// way the Appearance and Wallpaper pickers in System Settings do it.
    ///
    /// Outside is the load-bearing part: a border drawn ON the thumbnail paints
    /// inward over the very edge the reader is being asked to judge. That is
    /// true in both rows and it is not the same reason in each — which is why
    /// the sentence naming it stays at the call site and only the drawing
    /// lives here.
    func thumbnailSelectionRing(isSelected: Bool) -> some View {
        thumbnailHairline()
            .padding(Thumbnail.ringInset)
            .overlay {
                RoundedRectangle(
                    cornerRadius: Thumbnail.cornerRadius + Thumbnail.ringInset,
                    style: .continuous
                )
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
            }
    }

    /// The hairline alone, for a picture that is not an option — the one heading
    /// each display row says what that screen draws and selects nothing, so it
    /// wears the tiles' frame without their ring.
    func thumbnailHairline() -> some View {
        overlay {
            RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}
