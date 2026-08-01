import AppKit
import SwiftUI

/// Pick the Card's indicator by looking at it.
///
/// Two pictures instead of two nouns: "Line" and "Filled" name bodies the reader
/// has not seen yet, and the entire difference between them is visual — the same
/// reason the style tiles beside this row are pictures. Each tile renders the REAL
/// HUD body (`CardHUDIndicator`) frozen at one level, so the preview cannot come
/// to describe a bar the app no longer draws: a hand-drawn likeness would be a
/// second description of the indicator, and the second description is the one that
/// rots.
///
/// Whether this row exists at all is the CALLER's question, not this view's: it is
/// offered only where some connected display renders Card. That gate is an
/// EXISTENCE one — the row is absent rather than greyed out — because the sentence
/// a greyed row needed ("applies to the Card style, which is chosen in the General
/// tab") was paying for the distance to that picker, and there is no distance left
/// to pay for beside it (docs/DECISIONS.md: rendered-style-gates-settings).
struct IndicatorPicker: View {
    /// The persisted rawValue rather than the enum, because the caller holds this
    /// choice in `@AppStorage` on the same key the panels read. It also keeps the
    /// degrade-unknown-value rule where it belongs (`Preferences`): a stored value
    /// no tile matches selects none of them — the truthful picture — and nothing is
    /// written until a person picks.
    @Binding var selection: String
    /// The desk the tiles stand on, seeded once by whoever opened the window
    /// (`WallpaperTileStore`); nil is a complete answer — the tiles draw their own.
    /// Deliberately without a default, unlike the style picker's: this row shares a
    /// Section with that one, so a caller that forgot the scenery would put drawn
    /// desks beside real ones in the same picture. Required, it is a compile error
    /// instead.
    let wallpaper: NSImage?

    var body: some View {
        // The gap the style tiles above use, so the two rows read as one grid
        // rather than as two controls that happen to be stacked.
        HStack(alignment: .top, spacing: 4) {
            ForEach(HUDIndicatorStyle.allCases, id: \.rawValue) { style in
                IndicatorTile(
                    style: style,
                    wallpaper: wallpaper,
                    isSelected: style.rawValue == selection
                ) { selection = style.rawValue }
            }
        }
        // One control, two options: without this the buttons are read out as
        // unrelated and the row's own label never reaches them.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "settings.hud.indicator", defaultValue: "Card indicator"))
    }
}

/// One option: the picture, its name, and the selection ring.
private struct IndicatorTile: View {
    let style: HUDIndicatorStyle
    let wallpaper: NSImage?
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                // The ring goes OUTSIDE the picture, the way the Appearance and
                // Wallpaper pickers in System Settings do it. Drawn as a border on
                // the picture it would paint inward over the surface's own edge —
                // and the edge is part of what is being chosen here, since the
                // `.filled` bar meets it and the capsule does not.
                picture
                    .overlay {
                        RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous)
                            .strokeBorder(.separator, lineWidth: 0.5)
                    }
                    .padding(Thumbnail.ringInset)
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: Thumbnail.cornerRadius + Thumbnail.ringInset,
                            style: .continuous
                        )
                        .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2.5)
                    }
                Text(style.displayName)
                    .font(.callout)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
        }
        // Plain, because the tile IS the control: a bordered button would draw a
        // second frame around a picture that already has one.
        .buttonStyle(.plain)
        .contentShape(.rect)
        .accessibilityLabel(style.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    /// The desk with the indicator on it. A CLOSE-UP of one HUD, not a picture of
    /// a screen: the style tiles beside it own the "shape in a place" question, and
    /// a second menu bar and slit here would ask the reader to compare screens
    /// again when the only thing that differs is the bar.
    private var picture: some View {
        // The surface rides as an OVERLAY, which never votes on layout: it is drawn
        // at its real size and only then scaled, so as a stacked child it would
        // push this tile around from the inside.
        TileBackdrop(wallpaper: wallpaper)
            .overlay { surface }
            .frame(width: IndicatorThumbnail.width, height: IndicatorThumbnail.height)
            .clipShape(RoundedRectangle(cornerRadius: Thumbnail.cornerRadius, style: .continuous))
            .accessibilityHidden(true)   // the tile's own label names it
    }

    /// The indicator, drawn by the view the Card itself draws, at the Card's own
    /// HUD size, and scaled down whole. Laying it out at tile size instead would
    /// rearrange fixed metrics — the icon column, the horizontal padding, the 4 pt
    /// track — into a composition no card ever shows, and a preview of an
    /// arrangement that does not exist is a preview of nothing.
    private var surface: some View {
        ZStack {
            // A flat stand-in for the card's material, never `vibrantSurface`:
            // that material blends what is behind the WINDOW, so inside Settings
            // it would sample the desktop behind the pane instead of the desk
            // drawn right here — a hole in the picture where the surface should be.
            RoundedRectangle(cornerRadius: CardMetrics.hudSystemCornerRadius, style: .continuous)
                .fill(Color.black.opacity(IndicatorThumbnail.surfaceOpacity))
            CardHUDIndicator(
                kind: IndicatorThumbnail.sample.kind,
                presentation: HUDPresentation(hud: IndicatorThumbnail.sample),
                indicatorStyle: style,
                isHovered: false,
                onChange: { _ in },
                onRelease: {}
            )
        }
        .frame(width: CardMetrics.hudSystemWidth, height: CardMetrics.hudSystemHeight)
        // The `.filled` body is full-bleed and takes its corners from its HOST's
        // clip — the card's `vibrantSurface` there, this stand-in here. Without a
        // clip its sweep draws square through a rounded surface.
        .clipShape(RoundedRectangle(cornerRadius: CardMetrics.hudSystemCornerRadius, style: .continuous))
        // One flat hairline where the real surface draws a ramp, taken at the
        // ramp's brightest point: an edge that fades reads as no edge at this size.
        // Its width is authored INSIDE the scaled subtree, so it is pre-divided by
        // the scale — otherwise the half-point line arrives as a fifth of one,
        // finer than the pixel grid, and disappears the same way a faded edge does.
        .overlay {
            RoundedRectangle(cornerRadius: CardMetrics.hudSystemCornerRadius, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(SurfaceChrome.tileStrokeTopOpacity),
                    lineWidth: IndicatorThumbnail.surfaceStrokeWidth
                )
        }
        // Pinned dark ENCLOSING the surface, as the card pins it: the HUD's ink is
        // drawn for a dark surface, so in a light Settings window the glyph would
        // otherwise arrive black on black (docs/DECISIONS.md: hud-fixed-dark-palette).
        .environment(\.colorScheme, .dark)
        .scaleEffect(IndicatorThumbnail.scale)
        // A preview, not a control: the bar underneath is the live slider, whose
        // drag would otherwise take the pointer before the tile's own click.
        .allowsHitTesting(false)
    }
}

/// What a close-up of the HUD needs. The framing the two rows share — the corner
/// the picture is clipped to and the room the selection ring takes outside it —
/// comes from `Thumbnail` instead, so a style tile and an indicator tile cannot
/// come to sit in differently shaped frames.
private enum IndicatorThumbnail {
    /// The style tiles' width, taken rather than chosen: the two rows sit in one
    /// Section, so their tiles line up column by column, and a width picked here
    /// would drift out of that alignment the first time the row above is resized.
    static let width = Thumbnail.width
    /// Room for the scaled surface plus desk around it. The one measurement that is
    /// this row's own: a close-up owes no aspect ratio to any hardware, which is
    /// what the screen tiles owe theirs to. What it owes is margin — a surface
    /// touching the frame reads as cropped rather than as a surface on a desk.
    static let height: CGFloat = 36
    /// How much of the tile's width the surface takes. The framing knob: the scale
    /// follows from it, so a resized tile keeps its composition.
    static let surfaceWidthFraction: CGFloat = 0.8
    static let scale = width * surfaceWidthFraction / CardMetrics.hudSystemWidth
    /// The hairline as authored inside the scaled subtree, so that it LANDS at the
    /// width `SurfaceChrome` asked for.
    static let surfaceStrokeWidth = SurfaceChrome.outerHairlineWidth / scale
    /// The stand-in surface's darkness — the same value the style tiles give a
    /// floating surface, and for the same reason: it stands in for a material that
    /// cannot be drawn here, dark enough that the bar on it reads as the app's
    /// (docs/DECISIONS.md: hud-fixed-dark-palette).
    static let surfaceOpacity = 0.62
    /// The reading both tiles freeze at. ONE sample for both, because what the pair
    /// exists to show is the difference between the bodies — two levels would let
    /// the eye read that difference as a difference in loudness instead. Volume is
    /// the kind every Mac has (a Mac with no keyboard backlight never sees that
    /// HUD), and 0.7 keeps both a fill and a remainder visible: at either end of
    /// the scale the two bodies converge on a plain rectangle.
    static let sample = SystemHUD(kind: .volume, value: 0.7)
}
