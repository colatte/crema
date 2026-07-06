/// Pure presentation mapping for a HUD event: which SF Symbol and which slider
/// value a skin should show. Shared by all styles and unit-testable.
struct HUDPresentation: Equatable {
    var iconSystemName: String
    var value: Double

    init(hud: SystemHUD) {
        value = hud.value
        switch hud.kind {
        case .volume:
            iconSystemName = hud.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .screenBrightness:
            iconSystemName = "sun.max.fill"
        case .keyboardBrightness:
            iconSystemName = "keyboard"
        }
    }
}
