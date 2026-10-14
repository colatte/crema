import AppKit
import SwiftUI

/// Pick where the Card draws its HUD by looking at the place.
///
/// Eight small screens on a three-by-three grid, each where its place is on the
/// glass, the centre cell empty: the grid is the map, and a tile is a place, so
/// it carries no word under it — the name is its tooltip and what VoiceOver
/// reads. Each bar is put on its tile by the Card's own placement rule
/// (`StylePreview.hudBar(at:)`), so a tile cannot come to show a spot the HUD no
/// longer goes to; a drawn likeness would be the second description that rots.
///
/// Offered beside the indicator row, where some display draws Card: the caller
/// owns that gate (docs/DECISIONS.md: rendered-style-gates-settings).
struct HUDPlacementPicker: View {
    /// The persisted rawValue, for the reason `IndicatorPicker.selection` gives:
    /// the caller holds it in `@AppStorage` on the key the panels read.
    @Binding var selection: String
    /// The desk the tiles stand on; nil draws the fallback desk
    /// (`TileBackdrop`). Required for the reason `IndicatorPicker.wallpaper` is.
    let wallpaper: NSImage?

    var body: some View {
        Grid(horizontalSpacing: PlacementThumbnail.spacing, verticalSpacing: PlacementThumbnail.spacing) {
            ForEach(PlacementThumbnail.grid.indices, id: \.self) { row in
                GridRow {
                    ForEach(PlacementThumbnail.grid[row].indices, id: \.self) { column in
                        if let placement = PlacementThumbnail.grid[row][column] {
                            PlacementTile(
                                placement: placement,
                                wallpaper: wallpaper,
                                isSelected: placement.rawValue == selection
                            ) { selection = placement.rawValue }
                        } else {
                            Color.clear
                                .frame(width: PlacementThumbnail.size.width, height: PlacementThumbnail.size.height)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        // Places on the glass do not mirror under a right-to-left interface, and
        // neither does their picture: mirrored, the grid and the bars' offsets
        // would show "Top left" on the right (HUDPlacement).
        .environment(\.layoutDirection, .leftToRight)
        // One control, eight options, read out under the row's own label.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.hud.placement", defaultValue: "Position"))
    }
}

/// One option: the screen with the bar on it, and the selection ring.
private struct PlacementTile: View {
    let placement: HUDPlacement
    let wallpaper: NSImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            // Outside, as on every tile in this pane: a ring drawn on the picture
            // would paint over the screen edge the bar is placed against.
            picture
                .thumbnailSelectionRing(isSelected: isSelected)
        }
        // Plain, because the tile IS the control (see `IndicatorPicker`).
        .buttonStyle(.plain)
        .contentShape(.rect)
        .help(placement.displayName)
        .accessibilityLabel(placement.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private var picture: some View {
        let size = PlacementThumbnail.size
        let bar = PlacementThumbnail.barRect(for: placement)
        return ZStack(alignment: .topLeading) {
            TileBackdrop(wallpaper: wallpaper)
            ThumbnailMenuBar(width: size.width, height: PlacementThumbnail.menuBarHeight)
            PlacementBar(axis: placement.axis)
                .frame(width: bar.width, height: bar.height)
                .offset(x: bar.minX, y: bar.minY)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .accessibilityHidden(true)   // the tile's own label names it
    }
}

/// The bar in miniature: the floating surface, and a level filled from the bar's
/// start — the leading edge, or the bottom of an upright bar — which is what makes
/// it read as a level, and which way it runs, at this size.
private struct PlacementBar: View {
    let axis: Axis

    var body: some View {
        RoundedRectangle(cornerRadius: PlacementThumbnail.barCornerRadius, style: .continuous)
            .fill(Color.black.opacity(Thumbnail.floatingSurfaceOpacity))
            .overlay(alignment: CapsuleTrack.startAlignment(axis: axis)) {
                GeometryReader { geometry in
                    let length = CapsuleTrack.length(of: geometry.size, axis: axis)
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(along: axis, length * PlacementThumbnail.level)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: CapsuleTrack.startAlignment(axis: axis)
                        )
                }
                .padding(PlacementThumbnail.levelInset)
            }
    }
}

/// The numbers and the one rule the placement tiles are drawn by.
enum PlacementThumbnail {
    /// The tiles' places on the grid, as they sit on the glass; the centre has none.
    static let grid: [[HUDPlacement?]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, nil, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight],
    ]

    static let spacing = Thumbnail.smallTileSpacing
    /// Three across have to fit the row beside its label in the 500 pt Settings
    /// window, and three down add to the pane's height, so the tile is as small as
    /// keeps a bar and its edge legible.
    static let width: CGFloat = 64
    /// The reference panel's proportions (`StylePreview`), the screen every
    /// picture in this pane draws when it speaks for all displays.
    static let size = CGSize(width: width, height: width / screen.aspectRatio)
    static let menuBarHeight = Thumbnail.menuBarHeight(fraction: screen.menuBar, pictureHeight: size.height)
    /// How much larger than faithful the bar is drawn. A 210 pt bar on a 1512 pt
    /// screen is a 9 pt sliver here, under 2 pt thick, which reads as a line rather
    /// than as the HUD; the exaggeration keeps its proportions, so a flat bar and
    /// an upright one stay the same strip.
    static let barBoost: CGFloat = 2.5
    static let barCornerRadius: CGFloat = 1.5
    /// The level every tile shows, frozen: enough fill to tell where it starts.
    static let level: CGFloat = 0.6
    static let levelInset: CGFloat = 1

    private static let screen = StylePreview.shapes(for: .card)

    /// Where `placement`'s bar is drawn on a tile, in points, y down. Its size is
    /// the rule's, magnified; its place keeps the rule's share of the room around
    /// it, so a corner stays a corner and a centre a centre once the bar is larger.
    /// Then it clears the tile's frame and the menu bar by the floating clearance,
    /// the gap every floating surface keeps in these pictures — the rule's own 16 pt
    /// margin is under a point here.
    static func barRect(for placement: HUDPlacement) -> CGRect {
        let unit = StylePreview.hudBar(at: placement)
        let drawn = CGSize(
            width: unit.width * size.width * barBoost,
            height: unit.height * size.height * barBoost
        )
        let clearance = Thumbnail.floatingClearance
        let x = share(of: unit.minX, room: 1 - unit.width) * (size.width - drawn.width)
        let y = share(of: unit.minY, room: 1 - unit.height) * (size.height - drawn.height)
        return CGRect(
            x: min(max(x, clearance), size.width - clearance - drawn.width),
            y: min(max(y, menuBarHeight + clearance), size.height - clearance - drawn.height),
            width: drawn.width,
            height: drawn.height
        )
    }

    /// How far along the room around it an edge sits, 0 at the start and 1 at the
    /// end; the middle when there is no room to share.
    private static func share(of offset: CGFloat, room: CGFloat) -> CGFloat {
        room > 0 ? offset / room : 0.5
    }
}
