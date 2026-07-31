import CoreGraphics

/// The shapes a style's preview draws, as fractions of the preview screen
/// (0...1 on both axes, y measured DOWN like SwiftUI) so a view scales them into
/// any canvas without knowing a single point size.
struct StylePreviewShapes: Equatable {
    /// Where the surface sits, as a fraction of the screen.
    let surface: CGRect
    /// The physical slit, drawn only for the style that hugs it. Nil elsewhere:
    /// the notch is the subject of that one illustration, not scenery, and drawing
    /// it under the floating styles would show hardware they ignore — and would
    /// promise a notch to someone whose Mac has none.
    let slit: CGRect?
    /// Height of the menu bar strip, as a fraction of the screen.
    ///
    /// Scenery rather than rule output, and the only invented number here. It is a
    /// size reference for the top edge — it makes the slit read as a bite taken out
    /// of the bar, which is what a notch IS to the eye — and nothing more. It does
    /// NOT show the card floating underneath, because the card does not float
    /// underneath: on a slitless panel `safeTop` is 0, so the rule anchors the card
    /// 8 pt down (CardStyle) and it covers two thirds of a 24 pt bar. The
    /// difference between the two top-edge skins is carried by MATERIAL, below.
    let menuBar: CGFloat

    /// Whether the surface takes no material and is drawn opaque. The one fact
    /// about a skin's look that no frame rule can produce, and it is what separates
    /// the two skins that both hug the top edge: the notch style is opaque black so
    /// it camouflages with the hardware cutout, while the card and classic are a
    /// translucent material behind a 0.5 pt white hairline (`vibrantSurface`).
    /// Painting all three solid black made the card read as part of the bezel,
    /// which is exactly what it is not.
    let surfaceIsOpaque: Bool

    /// Whether the surface is welded to the top of the screen rather than floating
    /// under it. Read off the rule's own answer instead of declared per style, so a
    /// skin that stops hanging from the edge stops being drawn as if it did.
    var surfaceHangsFromTopEdge: Bool { surface.minY < 0.0001 }
}

/// A picture of where each skin puts its surface, derived from the skin's OWN
/// frame rule instead of drawn by hand.
///
/// That derivation is the whole point: `frame(for:on:)` is a pure function of
/// (state, geometry), so the preview is computed from the same rule that places
/// the real panel and cannot drift from it. A hand-drawn thumbnail would be a
/// second description of the layout, and the second description is the one that
/// goes stale (the house already refuses that split for hover and clicks, which
/// both derive from the rendered surface — docs/DECISIONS.md: hover-follows-the-eye).
enum StylePreview {
    /// The panel of a 14-inch MacBook Pro, measured rather than recalled:
    /// 1512x982 points, a 32 pt safe area, and a 185 pt slit between the
    /// auxiliary areas. A canonical screen rather than whichever one is attached —
    /// the preview teaches WHERE a style sits, and one familiar panel says that
    /// more plainly than an arbitrary aspect ratio.
    static let notchedReference = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663,
        auxRight: 664
    )

    /// The same panel with no slit — what a frame rule sees on every external
    /// monitor and every Mac that never had a notch.
    static let plainReference = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))

    /// The state the preview freezes: a track playing, surface open.
    ///
    /// The open surface rather than the resting one, decided by measuring both. At
    /// rest all three skins are small tabs, and the notch and the card come out as
    /// nearly the same tab — the difference between them is a gap of well under a
    /// point once scaled to a thumbnail. Open, the silhouettes separate on their
    /// own: the notch is narrow and tall against the top edge, the card is wide and
    /// flat below it, the classic block sits low. A picture that cannot be told
    /// from the picture beside it is not a preview.
    private static let previewState = PresentationState.nowPlaying(
        NowPlaying(title: "", isPlaying: true, position: 0),
        expanded: true
    )

    static func shapes(for style: Style) -> StylePreviewShapes {
        // Notch is illustrated on the only hardware it exists on; the floating
        // skins on a plain panel. Not `resolved(on:)` against one shared screen:
        // that would draw Notch and Card identically on a slitless reference and
        // leave the picker with two options that look the same, when the thing to
        // teach is what each style IS. The Settings footer already carries the
        // other half — that a notch declaration falls back to card where there is
        // no slit.
        let geometry = style == .notch ? notchedReference : plainReference
        let screen = geometry.frame
        // On a notched panel the safe area stands in for the bar. They are not the
        // same height — the bar is measured at 37 pt against the slit's 32
        // (docs/design-reference.md), and that gap is the classic gotcha of this
        // hardware — but the safe area is the number the rules already agree on,
        // and the 0.35 pt the difference is worth here does not buy a second
        // invented constant in the file whose whole argument is derive, don't
        // declare. On a plain panel it is the platform's own 24 pt.
        let bar = geometry.safeTop > 0 ? geometry.safeTop : 24
        return StylePreviewShapes(
            surface: unit(style.frame(for: previewState, on: geometry), in: screen),
            slit: style == .notch ? unit(slit(of: geometry), in: screen) : nil,
            menuBar: bar / screen.height,
            surfaceIsOpaque: style == .notch
        )
    }

    /// The slit as a rect: the top `safeTop` band between the auxiliary areas.
    private static func slit(of geometry: ScreenGeometry) -> CGRect {
        CGRect(
            x: geometry.frame.minX + geometry.auxLeft,
            y: geometry.frame.maxY - geometry.safeTop,
            width: geometry.frame.width - geometry.auxLeft - geometry.auxRight,
            height: geometry.safeTop
        )
    }

    /// AppKit's y-up screen space to SwiftUI's y-down unit space. The flip lives
    /// here, once, rather than in a view: it is the kind of sign that is silently
    /// wrong for a style anchored to the bottom and obviously right for one
    /// anchored to the top.
    private static func unit(_ rect: CGRect, in screen: CGRect) -> CGRect {
        guard screen.width > 0, screen.height > 0 else { return .zero }
        return CGRect(
            x: (rect.minX - screen.minX) / screen.width,
            y: (screen.maxY - rect.maxY) / screen.height,
            width: rect.width / screen.width,
            height: rect.height / screen.height
        )
    }
}
