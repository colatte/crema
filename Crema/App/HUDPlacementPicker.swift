import AppKit
import SwiftUI

/// Pick where the Card draws its HUD by pointing at the place, on one screen.
///
/// The screen is drawn like every Settings picture — the user's desk, the menu bar
/// — with the card resting at the top, where it stays while the HUD shows
/// elsewhere, and the seven other places the HUD can go drawn on it, dimmed; the
/// chosen one is lit and ringed. The card is itself the eighth choice: at the top
/// centre the HUD IS the card, morphed, so choosing it draws the bar in the card's
/// place. Every shape is
/// the Card's own rule on the reference panel (`StylePreview.restingCard`,
/// `StylePreview.hudBar(at:)`), magnified alike so the bar keeps its true size
/// beside the card; a drawn likeness would be the second description that rots.
///
/// Offered beside the indicator row, where some display draws Card: the caller
/// owns that gate (docs/DECISIONS.md: rendered-style-gates-settings).
struct HUDPlacementPicker: View {
    /// The persisted rawValue, for the reason `IndicatorPicker.selection` gives:
    /// the caller holds it in `@AppStorage` on the key the panels read.
    @Binding var selection: String
    /// The desk the picture stands on; nil draws the fallback desk
    /// (`TileBackdrop`). Required for the reason `IndicatorPicker.wallpaper` is.
    let wallpaper: NSImage?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: HUDPlacement?
    /// Drawn by the map itself rather than by the system: the system's ring traces
    /// the target, an invisible rect, and the picture's clip cuts it at the edges.
    @FocusState private var focused: HUDPlacement?

    var body: some View {
        ZStack(alignment: .topLeading) {
            TileBackdrop(wallpaper: wallpaper)
                .accessibilityHidden(true)
            ThumbnailMenuBar(width: PlacementMap.size.width, height: PlacementMap.menuBarHeight)
                .accessibilityHidden(true)
            ForEach(Array(HUDPlacement.allCases.enumerated()), id: \.element) { order, placement in
                // Read out in the order the places sit on the glass, top left
                // first, whatever order they are drawn in.
                option(placement)
                    .accessibilitySortPriority(Double(HUDPlacement.allCases.count - order))
            }
        }
        .frame(width: PlacementMap.size.width, height: PlacementMap.size.height)
        .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
        .thumbnailHairline()
        // The room the indicator tiles above give their rings, so the two pictures
        // of this Section stand in one column (`PlacementMap.width`).
        .padding(Thumbnail.ringInset)
        .animation(PlacementMap.change(reduceMotion: reduceMotion), value: selection)
        .animation(PlacementMap.change(reduceMotion: reduceMotion), value: hovered)
        .animation(PlacementMap.change(reduceMotion: reduceMotion), value: focused)
        // Places on the glass do not mirror under a right-to-left interface, and
        // neither does their picture: mirrored, the offsets would draw "Top left"
        // on the right (HUDPlacement).
        .environment(\.layoutDirection, .leftToRight)
        // One control, eight options, read out under the row's own label.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.hud.placement", defaultValue: "Position"))
    }

    /// One place: a target larger than its mark, so a bar a few points thick is
    /// still easy to hit, with the mark drawn where the rule puts it inside.
    private func option(_ placement: HUDPlacement) -> some View {
        let chosen = placement.rawValue == selection
        let target = PlacementMap.target(for: placement)
        return Button {
            selection = placement.rawValue
        } label: {
            ZStack(alignment: .topLeading) {
                Color.clear
                mark(placement, chosen: chosen, ring: ring(chosen: chosen, placement: placement))
            }
            .frame(width: target.width, height: target.height)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .focused($focused, equals: placement)
        .focusEffectDisabled()
        .offset(x: target.minX, y: target.minY)
        .onHover { inside in
            if inside {
                hovered = placement
            } else if hovered == placement {
                hovered = nil
            }
        }
        .help(placement.displayName)
        .accessibilityLabel(placement.displayName)
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : [.isButton])
    }

    /// The one ring a place wears, if any: keyboard focus over selection over the
    /// pointer's hint, which is thinner, so a hover never reads as a choice.
    private func ring(chosen: Bool, placement: HUDPlacement) -> PlacementRing.Kind? {
        if focused == placement { return .focus }
        if chosen { return .selection }
        if hovered == placement { return .hover }
        return nil
    }

    /// What a place draws, in its target's own coordinates. The top centre is the
    /// card while the HUD goes elsewhere, and the HUD in the card's place once it
    /// is chosen.
    @ViewBuilder
    private func mark(_ placement: HUDPlacement, chosen: Bool, ring: PlacementRing.Kind?) -> some View {
        let origin = PlacementMap.target(for: placement).origin
        if placement == .topCenter, !chosen {
            let card = PlacementMap.cardRect.offsetBy(dx: -origin.x, dy: -origin.y)
            PreviewSurface(
                size: card.size,
                isOpaque: false,
                hangsFromTopEdge: false,
                arrangement: .coverBesideTwoLines,
                cornerRadius: PlacementMap.cardCornerRadius
            )
            .overlay {
                if let ring {
                    PlacementRing(kind: ring, cornerRadius: PlacementMap.cardCornerRadius)
                }
            }
            .offset(x: card.minX, y: card.minY)
            .transition(.opacity)
        } else {
            let bar = PlacementMap.barRect(for: placement).offsetBy(dx: -origin.x, dy: -origin.y)
            PlacementBar(axis: placement.axis, emphasis: chosen ? .chosen : ring == .hover ? .hovered : .resting)
                .overlay {
                    if let ring {
                        PlacementRing(kind: ring, cornerRadius: PlacementMap.barCornerRadius)
                    }
                }
                .frame(width: bar.width, height: bar.height)
                .offset(x: bar.minX, y: bar.minY)
                .transition(.opacity)
        }
    }
}

/// The HUD in miniature: a dark bar with the border every floating surface wears
/// in these pictures and a level filled from the bar's start — the leading edge,
/// or the bottom of an upright bar — which is what makes it read as a level, and
/// which way it runs, at this size.
private struct PlacementBar: View {
    enum Emphasis { case resting, hovered, chosen }

    let axis: Axis
    let emphasis: Emphasis

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: PlacementMap.barCornerRadius, style: .continuous)
        shape
            .fill(Color.black.opacity(surface))
            .previewDepth(floats: emphasis == .chosen)
            .overlay(alignment: CapsuleTrack.startAlignment(axis: axis)) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(.white.opacity(level))
                        .frame(along: axis, CapsuleTrack.length(of: geometry.size, axis: axis) * PlacementMap.level)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity,
                            alignment: CapsuleTrack.startAlignment(axis: axis)
                        )
                }
                .padding(PlacementMap.levelInset)
            }
            .overlay {
                shape.strokeBorder(.white.opacity(border), lineWidth: SurfaceChrome.specularWidth)
            }
    }

    /// Resting places recede so the chosen one is the only bar that reads as the
    /// HUD; the pointer lifts a place halfway, as a hint of what a click picks.
    private var surface: Double {
        switch emphasis {
        case .resting: 0.3
        case .hovered: 0.5
        case .chosen: Thumbnail.floatingSurfaceOpacity
        }
    }

    private var level: Double {
        switch emphasis {
        case .resting: 0.35
        case .hovered: 0.7
        case .chosen: 0.9
        }
    }

    private var border: Double {
        switch emphasis {
        case .resting: 0.2
        case .hovered: 0.35
        case .chosen: SurfaceChrome.tileStrokeTopOpacity
        }
    }
}

/// The ring around a place, outside its mark, as the selection ring sits outside
/// every Settings picture: drawn on the mark it would paint over the very edge the
/// reader is judging.
private struct PlacementRing: View {
    enum Kind { case selection, focus, hover }

    let kind: Kind
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius + PlacementMap.ringInset, style: .continuous)
            .strokeBorder(style, lineWidth: kind == .hover ? PlacementMap.hoverRingWidth : PlacementMap.ringWidth)
            .padding(-PlacementMap.ringInset)
    }

    /// The selection takes the tint every Settings ring takes; focus, the colour
    /// the system draws keyboard focus in; the pointer's hint stays neutral.
    private var style: AnyShapeStyle {
        switch kind {
        case .selection: AnyShapeStyle(.tint)
        case .focus: AnyShapeStyle(Color(nsColor: .keyboardFocusIndicatorColor))
        case .hover: AnyShapeStyle(Color.white.opacity(0.5))
        }
    }
}

/// The picture's geometry: one pure rule for where everything sits, so the map is
/// pinned by tests rather than by eye.
enum PlacementMap {
    /// The span of the two indicator pictures above it, ring room included, so the
    /// two pictures of one Section stand in one column; wide enough that a bar a
    /// few points thick is still a target worth aiming at.
    static let width: CGFloat = 2 * Thumbnail.width + Thumbnail.smallTileSpacing + 2 * Thumbnail.ringInset
    /// The reference panel's proportions (`StylePreview`), the screen every
    /// picture in this pane draws when it speaks for all displays.
    static let size = CGSize(width: width, height: width / screen.aspectRatio)
    static let menuBarHeight = Thumbnail.menuBarHeight(fraction: screen.menuBar, pictureHeight: size.height)
    /// One magnification for the card and the bar alike. Faithful, a 1512 pt
    /// screen leaves the HUD a 33 pt sliver under 7 pt thick; magnified alike, the
    /// two keep the proportion they have on screen — the HUD is smaller than the
    /// card — instead of one of them being exaggerated alone.
    static let magnification: CGFloat = 1.6
    /// How far a target reaches beyond its mark, on every side the picture allows.
    static let hitSlop: CGFloat = 6
    /// The real HUD's corner, as a share of its thickness, so the miniature bar is
    /// rounded the way the bar on screen is.
    static var barCornerRadius: CGFloat {
        barRect(for: .bottomCenter).height * CardMetrics.hudSystemCornerRadius / CardMetrics.hudSystemHeight
    }

    /// The real card's corner, as a share of its height: the card is rounder than
    /// the HUD on screen, and so in the picture.
    static var cardCornerRadius: CGFloat {
        cardRect.height * CardMetrics.cornerRadius / CardMetrics.compact.height
    }

    /// The level every bar shows, frozen: enough fill to tell where it starts.
    static let level: CGFloat = 0.6
    static let levelInset: CGFloat = 1.5
    static let ringInset: CGFloat = 2.5
    static let ringWidth: CGFloat = 2
    static let hoverRingWidth: CGFloat = 1
    /// How far every mark keeps from the picture's frame and from the menu bar:
    /// the room its ring takes, plus a hair, so a chosen place on an edge is
    /// ringed whole instead of clipped against the frame. The rule's own 16 pt
    /// margin is under three points here, so this is what a mark keeps instead.
    static let edgeRoom: CGFloat = ringInset + ringWidth + 1.5

    static func change(reduceMotion: Bool) -> Animation? {
        SurfaceAnimation.respecting(reduceMotion: reduceMotion, .easeOut(duration: 0.18))
    }

    private static let screen = StylePreview.shapes(for: .card)
    private static var bounds: CGRect { CGRect(origin: .zero, size: size) }

    /// The card at rest, top-centred, hanging from the same line as the bars along
    /// the top, as on screen every top surface hangs from one anchor.
    static var cardRect: CGRect {
        let unit = StylePreview.restingCard()
        let drawn = CGSize(width: unit.width * size.width * magnification, height: unit.height * size.height * magnification)
        return CGRect(
            x: unit.midX * size.width - drawn.width / 2,
            y: max(unit.minY * size.height, menuBarHeight + edgeRoom),
            width: drawn.width,
            height: drawn.height
        )
    }

    /// Where `placement`'s bar is drawn, in points, y down. Its size is the rule's,
    /// magnified; its place keeps the rule's share of the room around it, so a
    /// corner stays a corner and a centre a centre once the bar is larger. Then it
    /// keeps `edgeRoom` from the picture's frame and from the menu bar.
    static func barRect(for placement: HUDPlacement) -> CGRect {
        let unit = StylePreview.hudBar(at: placement)
        let drawn = CGSize(width: unit.width * size.width * magnification, height: unit.height * size.height * magnification)
        let x = share(of: unit.minX, room: 1 - unit.width) * (size.width - drawn.width)
        let y = share(of: unit.minY, room: 1 - unit.height) * (size.height - drawn.height)
        return CGRect(
            x: min(max(x, edgeRoom), size.width - edgeRoom - drawn.width),
            y: min(max(y, menuBarHeight + edgeRoom), size.height - edgeRoom - drawn.height),
            width: drawn.width,
            height: drawn.height
        )
    }

    /// What a click on `placement` lands on: its mark — for the top centre both the
    /// card and the bar that replaces it — and `hitSlop` around it, within the
    /// picture.
    static func target(for placement: HUDPlacement) -> CGRect {
        let mark = placement == .topCenter ? cardRect.union(barRect(for: .topCenter)) : barRect(for: placement)
        return mark.insetBy(dx: -hitSlop, dy: -hitSlop).intersection(bounds)
    }

    /// How far along the room around it an edge sits, 0 at the start and 1 at the
    /// end; the middle when there is no room to share.
    private static func share(of offset: CGFloat, room: CGFloat) -> CGFloat {
        room > 0 ? offset / room : 0.5
    }
}
