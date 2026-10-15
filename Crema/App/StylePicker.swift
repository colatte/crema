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
        // Ten points of air, and three tiles plus rings and gaps still fit the
        // ~440 pt Form row with room to spare (3 × 114 + 20 = 362); a tighter
        // strip reads as crowded.
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
        .accessibilityLabel(String(localized: "settings.general.style", defaultValue: "Style for all displays"))
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
                // the whole difference between these skins lives, and a border on the
                // thumbnail paints over the very thing being selected.
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
