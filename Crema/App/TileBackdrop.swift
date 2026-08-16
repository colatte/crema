import AppKit
import SwiftUI

/// The desk a style tile stands on.
///
/// It is the user's own desktop picture, because these tiles are pictures OF A
/// PLACE: each one says "the surface looks like this, up there on your screen",
/// and a screen wearing a wallpaper nobody has ever seen is a picture of somebody
/// else's Mac. What stood here before was a flat gradient, for two reasons that
/// both survive — in the VEIL, not in the substitute:
///
/// - The subject is the black shape, not the scenery. A wallpaper at full
///   contrast competes with the one thing these pictures exist to compare, so it
///   goes under a dark wash and stays background.
/// - The app's surfaces are always dark (docs/DECISIONS.md:
///   hud-fixed-dark-palette), so a tile that went bright under a pale wallpaper
///   would describe a skin the app never draws. The wash keeps every desk dark
///   enough for the surface standing on it to be honest.
///
/// The gradient stays as the fallback for a desk that cannot be read — no picture
/// reported, or a dynamic/aerial desktop ImageIO will not open — because a hole
/// where the screen should be is a worse picture than a drawn one
/// (docs/DECISIONS.md: tile-backdrop-is-the-real-desktop).
///
/// Sized by whoever places it: both halves fill the proposal and neither reports
/// a size of its own, so the tile's frame and clip stay the only authority on how
/// big the picture is.
struct TileBackdrop: View {
    let wallpaper: NSImage?

    var body: some View {
        if let wallpaper {
            // The clear box takes the proposed size and an overlay never votes on
            // layout: a fill-scaled image reports the size it grew to, which would
            // let a wide desktop picture push around the tile it is scenery for.
            Color.clear
                .overlay {
                    Image(nsImage: wallpaper)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
                .overlay { Color.black.opacity(Self.veilOpacity) }
        } else {
            Self.fallback
        }
    }

    /// How dark the wash is. Enough that a white desktop still reads as
    /// background behind a black surface; light enough that the picture stays
    /// recognisably the user's own desk rather than a grey rectangle. Raised
    /// from the first cut's 0.28 on a field verdict: over a pale sky that wash
    /// barely existed and the tiles read washed-out rather than staged.
    private static let veilOpacity = 0.35

    /// The drawn desk, for when there is no readable one. Flat and dim on
    /// purpose: it stands in for scenery, so it must not become the subject.
    static let fallback = LinearGradient(
        colors: [Color(red: 0.29, green: 0.33, blue: 0.42), Color(red: 0.17, green: 0.19, blue: 0.25)],
        startPoint: .top,
        endPoint: .bottom
    )
}
