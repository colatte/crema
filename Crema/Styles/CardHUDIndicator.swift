import SwiftUI

/// The Card's HUD body — the icon-and-bar arrangement each `HUDIndicatorStyle`
/// draws — as a view of explicit values, so the two places that show it draw the
/// same thing: the live Card surface (`CardView`) and the Settings picker, whose
/// mini-tiles render this body frozen (a fixed level, no-op intents, hit testing
/// off) as the choice's own preview. A tile that re-drew a likeness of the
/// indicator would be a second description of it, and the second description is
/// the one that rots — it would still show the old bar the day this one changes.
///
/// It draws no surface of its own: the host supplies the material, the radius and
/// the clip, and the `.filled` body depends on that clip to round its sweep (the
/// card's `vibrantSurface`, the tile's stand-in surface). A host without a
/// rounded clip gets square corners on the fused bar.
struct CardHUDIndicator: View {
    /// Kept beside `presentation` because the slider keys its identity on the kind
    /// — volume→brightness is an unrelated 0…1 scale, which must snap rather than
    /// glide through meaningless in-between levels — and names it to VoiceOver.
    let kind: SystemHUD.Kind
    /// Glyph and level in one value, built by the caller: from the live reading on
    /// the card, from a frozen sample in the picker. It stays outside because
    /// `HUDPresentation` reads the whole `SystemHUD` (mute has its own glyph), so
    /// kind and level alone could not reconstruct it here.
    let presentation: HUDPresentation
    let indicatorStyle: HUDIndicatorStyle
    /// The panel-local pointer signal that reveals the capsule knob
    /// (`SurfaceDisplayPolicy.pointerInside` on the card; always false in the
    /// picker, whose tile is a preview and not a control).
    let isHovered: Bool
    let onChange: (Double) -> Void
    let onRelease: () -> Void
    /// The direction the bar runs: horizontal by default; `HUDPlacement.axis`
    /// names the placements where it stands upright. Upright, the glyph sits
    /// under the bar, where the level starts.
    var axis: Axis = .horizontal
    /// The bar's answer to a press (`HUDLevelSlider.press`, `isEngaged`); the
    /// picker's frozen tile leaves both at rest.
    var press: HUDPress?
    var isEngaged = false

    /// Fixed slot for the glyph along the bar — a column beside a horizontal bar,
    /// a row under an upright one — owned here because the glyph is drawn here;
    /// the skins' Metrics derive from it rather than each declaring 22. The
    /// volume family steps through four symbols of different widths as the level
    /// moves (`HUDPresentation`), so without a fixed slot each swap would shift
    /// the bar beside it — motion the level animation would then carry.
    nonisolated static let hudIconSlot: CGFloat = 22

    @ViewBuilder var body: some View {
        switch indicatorStyle {
        case .slider:
            // Icon beside the capsule row (the Notch's layout too), or under it
            // when the bar stands upright; Classic keeps its bezel's segmented
            // bar. The padding along the bar is the card's horizontal content
            // padding, turned with it.
            if axis == .horizontal {
                HStack(spacing: CardMetrics.contentGap) {
                    // Pinned to the column's leading edge, not centred in it: the
                    // column is wider than the narrowest glyph of the family, so a
                    // centred symbol slides sideways on every swap — the exact
                    // motion the fixed column exists to remove.
                    sliderGlyph.frame(width: Self.hudIconSlot, alignment: .leading)
                    slider(appearance: HUDLevelSlider.appearance(for: indicatorStyle))
                }
                .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
            } else {
                VStack(spacing: CardMetrics.contentGap) {
                    slider(appearance: HUDLevelSlider.appearance(for: indicatorStyle))
                    // Centred across the bar: upright, a width change grows the
                    // glyph about its centre and moves nothing else, because the
                    // bar sits above it and the row's height is fixed.
                    sliderGlyph.frame(height: Self.hudIconSlot)
                }
                .padding(.vertical, CardMetrics.contentPaddingHorizontal)
            }
        case .filled:
            // Fused, full-bleed: the bar fills the whole HUD frame (no padding,
            // no inner track) and the HOST's rounded-rect clip rounds the sweep —
            // the card's own (cardSurface), the picker tile's on its stand-in
            // surface. The icon rides inside at the bar's start, over the fill at
            // high levels and the remainder at low ones, and inverts what lies
            // beneath it (CardMetrics.hudFilledGlyph says why).
            slider(appearance: .filled)
                .overlay(alignment: CapsuleTrack.startAlignment(axis: axis)) {
                    Image(systemName: presentation.iconSystemName)
                        .foregroundStyle(.white)
                        .blendMode(.difference)
                        .padding(CapsuleTrack.startEdge(axis: axis), CardMetrics.hudFilledIconInset)
                        .accessibilityHidden(true)
                        // The bar underneath owns the whole drag/tap surface; the
                        // glyph is decoration and must let touches through to it.
                        .allowsHitTesting(false)
                        // Overlay glyph — a separate subtree from the fill below, so
                        // the swap animates the icon without touching the bar.
                        .symbolReplace(on: presentation.iconSystemName)
                }
        }
    }

    /// The `.slider` body's glyph, hidden from VoiceOver because the bar beside
    /// it already names the reading (HUDLevelSlider); the `.filled` body hides its
    /// own for the same reason.
    private var sliderGlyph: some View {
        Image(systemName: presentation.iconSystemName)
            .accessibilityHidden(true)
            .symbolReplace(on: presentation.iconSystemName)
    }

    private func slider(appearance: HUDLevelSlider.Appearance) -> HUDLevelSlider {
        HUDLevelSlider(
            kind: kind,
            value: presentation.value,
            onChange: onChange,
            onRelease: onRelease,
            appearance: appearance,
            isHovered: isHovered,
            axis: axis,
            press: press,
            isEngaged: isEngaged
        )
    }
}
