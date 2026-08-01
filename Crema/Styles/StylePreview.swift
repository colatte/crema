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
    /// Scenery rather than rule output: a size reference for the top edge, which
    /// makes the slit read as a bite taken out of the bar — what a notch IS to the
    /// eye. On a notched panel the safe area stands in for it; a slitless one
    /// reports zero safe area and still has a bar, so there it is the measured
    /// slitless height instead. Never zero on a real screen, because a picture with
    /// no top edge is not a picture of a Mac and leaves the floating surfaces with
    /// nothing to float under. What tells the two top-edge skins apart is the
    /// clearance (`surfaceClearsTheMenuBar`) and the shadow — and on a slitless
    /// panel the card really does cover two thirds of the bar (its rule reads the
    /// safe area and anchors 8 pt down), which is the honest picture of that
    /// display, not a defect of the drawing.
    let menuBar: CGFloat

    /// Whether the surface takes no material and is drawn opaque. One of the facts
    /// about a skin's look that no frame rule produces (`contentArrangement` below
    /// is the other), and the difference a user names first: only the notch style is
    /// black, because it camouflages with the hardware cutout it covers; the card
    /// and classic are a translucent material edged by `vibrantSurface`'s chrome
    /// pair — dark outer rim plus top specular (docs/DECISIONS.md:
    /// surface-border-2026).
    let surfaceIsOpaque: Bool

    /// How the surface arranges what it holds: a cover with the track's two lines
    /// beside it on the skins that live along the top edge, a cover above one line
    /// on the squarish classic block. Like `surfaceIsOpaque`, a fact about the skin
    /// that no frame rule produces — the rules answer where a surface goes, never
    /// what is inside it — and taken from the RESOLVED style rather than from the
    /// rect's proportions: those come from a calibration, so a card grown a few
    /// points taller would flip its miniature to the block's stack in silence.
    let contentArrangement: PreviewContentArrangement

    /// Width over height of the display these shapes describe. The fractions above
    /// carry no shape of their own, so a drawing that picks its own proportions
    /// draws some other Mac and moves every surface with it. Zero for a degenerate
    /// screen, the same answer the fractions give: there is nothing to draw.
    let aspectRatio: CGFloat

    /// Whether the surface is welded to the top of the screen rather than floating
    /// under it. Read off the rule's own answer instead of declared per style, so a
    /// skin that stops hanging from the edge stops being drawn as if it did.
    var surfaceHangsFromTopEdge: Bool { surface.minY < 0.0001 }

    /// Whether the surface clears the menu bar entirely, which is what a floating
    /// skin does and a welded one does not.
    ///
    /// Read by the drawing to keep that ORDER visible. The magnitude cannot be: the
    /// card's real clearance is 3 pt on a 982 pt screen, which is a fifth of a point
    /// once scaled into a 70 pt picture, so a faithful rendering puts the two edges
    /// on the same pixel and the card reads as welded — the exact complaint these
    /// pictures came back with, twice. What is exaggerated is only the size of a gap
    /// that is really there; where a surface really does touch the top edge, it is
    /// still drawn touching it.
    var surfaceClearsTheMenuBar: Bool { surface.minY >= menuBar }
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
    /// auxiliary areas. The default screen to be asked about: a picker that speaks
    /// for all displays at once has no single panel to describe, and one familiar
    /// Mac teaches WHERE a style sits more plainly than an arbitrary aspect ratio.
    static let notchedReference = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeTop: 32,
        auxLeft: 663,
        auxRight: 664
    )

    /// The menu bar of a display with no slit, measured: 24 pt. Used only where
    /// `safeTop` is 0 — a notched panel's safe area already stands in for its own
    /// bar, and the two are not the same height (37 pt against 32 on that panel).
    private static let slitlessMenuBarPoints: CGFloat = 24

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

    /// The shapes of one skin on one display, defaulting to the canonical panel.
    ///
    /// The default is what a picker speaking for every display asks for, and it is
    /// a NOTCHED panel on purpose: the card's own rule reads the safe area, so on a
    /// slitless one it anchors 8 pt from the top edge, under the bar, and the
    /// picture said the card was welded to the bezel. On the hardware this app was
    /// built for it is not — 32 pt of safe area plus its 8 pt margin puts it 40 pt
    /// down, clear of a 37 pt bar — and the field reported that as the thing the
    /// picture was getting wrong. Comparing three styles on three different screens
    /// is what let it happen, so one panel answers for all three unless the caller
    /// names a display.
    ///
    /// Named a display, the picture is of the skin that display RESOLVES to, never
    /// the declared one: asked for the notch on a slitless panel it draws the card,
    /// no slit, not opaque — what that Mac would really put on screen. Promising a
    /// notch to someone whose Mac has none is the same lie in a thumbnail that it
    /// would be on the panel. Resolving here is also why the notch rule's own
    /// slitless guard is never reached through this path: the declared→drawn
    /// mapping lives in one function and every reader asks IT
    /// (docs/DECISIONS.md: rendered-style-gates-settings).
    ///
    /// `on:` has no caller in the app today — the per-display control is a popup of
    /// names, not pictures — and it stays anyway: the resolution it selects is a
    /// rule embedded in the line below, and the suite is what pins it, so the
    /// parameter is the seam that reaches that rule rather than an unused argument
    /// (the same standing `Preferences.setShowsNowPlaying` has). The next caller is
    /// already named: tiles at the head of each per-display row, which would have to
    /// picture that row's own screen.
    static func shapes(
        for style: Style,
        on geometry: ScreenGeometry = Self.notchedReference
    ) -> StylePreviewShapes {
        let rendered = style.resolved(on: geometry)
        let screen = geometry.frame
        // The safe area stands in for the bar wherever there is one: it is the
        // number the rules already agree on, and the 0.35 pt it differs from this
        // panel's real 37 pt bar (docs/design-reference.md — the classic gotcha of
        // this hardware) does not buy a second constant in the file whose whole
        // argument is derive, don't declare. A slitless panel reports no safe area
        // and still has a bar, and that one has to be declared or the tile for
        // every Mac without a notch loses its top edge.
        let bar = geometry.safeTop > 0 ? geometry.safeTop : slitlessMenuBarPoints
        return StylePreviewShapes(
            surface: unit(rendered.frame(for: previewState, on: geometry), in: screen),
            slit: rendered == .notch ? unit(slit(of: geometry), in: screen) : nil,
            menuBar: fraction(bar, of: screen.height),
            surfaceIsOpaque: rendered == .notch,
            contentArrangement: rendered == .classic ? .coverAboveOneLine : .coverBesideTwoLines,
            aspectRatio: fraction(screen.width, of: screen.height)
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

    /// One guarded division for the numbers that are not rects, so a degenerate
    /// screen answers zero here too instead of dividing by it — the same answer
    /// `unit` gives, and the drawing has nothing to draw either way.
    private static func fraction(_ value: CGFloat, of extent: CGFloat) -> CGFloat {
        extent > 0 ? value / extent : 0
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
