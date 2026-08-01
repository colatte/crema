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

    @ViewBuilder var body: some View {
        switch indicatorStyle {
        case .slider:
            // Icon beside the capsule row (the Notch's layout too); Classic keeps its bezel's segmented bar.
            HStack(spacing: CardMetrics.contentGap) {
                Image(systemName: presentation.iconSystemName)
                    .frame(width: CardMetrics.hudIconColumnWidth)
                    .symbolReplace(on: presentation.iconSystemName)
                HUDLevelSlider(
                    kind: kind,
                    value: presentation.value,
                    onChange: onChange,
                    onRelease: onRelease,
                    appearance: HUDLevelSlider.appearance(for: indicatorStyle),
                    isHovered: isHovered
                )
            }
            .padding(.horizontal, CardMetrics.contentPaddingHorizontal)
        case .filled:
            // Fused, full-bleed: the bar fills the whole HUD frame (no padding,
            // no inner track) and the HOST's rounded-rect clip rounds the sweep —
            // the card's own (vibrantSurface), the picker tile's on its stand-in
            // surface. The icon rides inside at the leading edge, over the fill at
            // high levels and the dark remainder at low ones.
            HUDLevelSlider(
                kind: kind,
                value: presentation.value,
                onChange: onChange,
                onRelease: onRelease,
                appearance: .filled
            )
            .overlay(alignment: .leading) {
                Image(systemName: presentation.iconSystemName)
                    .foregroundStyle(CardMetrics.hudFilledIconColor)
                    .padding(.leading, CardMetrics.hudFilledIconLeading)
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
}
