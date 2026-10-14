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
    /// Room between the picture and the selection ring.
    fileprivate static let ringInset: CGFloat = 3
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
    /// How much wider than faithful the strip surfaces are drawn, and how much
    /// taller. Calibrated against the drawing the owner approved (surfaces at
    /// roughly 28-37% of the tile's width, cover at ~45% of their height), not
    /// to taste; the rationale for exaggerating at all is on `surfaceSize`.
    static let stripSurfaceWidthBoost: CGFloat = 2.0
    static let stripSurfaceHeightBoost: CGFloat = 1.35
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
