/// Pure presentation mapping for a HUD event: which SF Symbol a skin should
/// show for the event's kind and level, plus the slider value. Shared by all
/// styles and unit-testable — the level thresholds live here, in the pure
/// struct, not in the SF Symbols renderer, so every boundary is pinned by a
/// test and stays identical across the three styles and both Card variants.
struct HUDPresentation: Equatable {
    var iconSystemName: String
    var value: Double

    init(hud: SystemHUD) {
        value = hud.value
        iconSystemName = Self.icon(for: hud)
    }

    /// The speaker.wave family carries exactly three wave layers, and the native
    /// volume OSD reveals them one per third of the range; splitting 0...1 into
    /// equal thirds maps one wave per third. Upper edges are inclusive, so a
    /// value sitting exactly on a boundary keeps the lower step.
    private static let volumeLowThird = 1.0 / 3.0
    private static let volumeHighThird = 2.0 / 3.0

    /// Brightness (screen and keyboard) is a two-state glyph — dim vs bright.
    /// The cut is the midpoint, so the lower half reads as the min glyph and the
    /// upper half as the max, one boundary and no in-between ambiguity.
    private static let brightnessMidpoint = 0.5

    private static func icon(for hud: SystemHUD) -> String {
        switch hud.kind {
        case .volume:
            return volumeIcon(value: hud.value, isMuted: hud.isMuted)
        case .screenBrightness:
            return hud.value < brightnessMidpoint ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBrightness:
            // light.min / light.max are the classic keyboard-backlight glyphs;
            // the same midpoint cut as the screen keeps both brightnesses reading
            // low/high with one shared rule.
            return hud.value < brightnessMidpoint ? "light.min" : "light.max"
        }
    }

    /// Muted and silent are their own glyphs — a slashed speaker for mute, a
    /// bare speaker (no waves) at zero — matching the native HUD; above zero the
    /// waves grow one per third.
    private static func volumeIcon(value: Double, isMuted: Bool) -> String {
        if isMuted { return "speaker.slash.fill" }
        if value <= 0 { return "speaker.fill" }
        if value <= volumeLowThird { return "speaker.wave.1.fill" }
        if value <= volumeHighThird { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }
}
