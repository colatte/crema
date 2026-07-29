import CoreGraphics
@testable import Crema

/// Test fake for the window seam: records every frame it was asked to apply.
@MainActor
final class RecordingPanel: PresentationPanel {
    private(set) var appliedFrames: [CGRect] = []
    private(set) var hoverArmedStates: [Bool] = []
    private(set) var showsNowPlayingStates: [Bool] = []
    private(set) var showsHUDStates: [Bool] = []
    private(set) var showsControlsStates: [Bool] = []
    private(set) var hudIndicatorStyleStates: [HUDIndicatorStyle] = []
    private(set) var invokeZones: [CGRect?] = []
    private(set) var closed = false

    // swiftlint:disable:next function_parameter_count
    func apply(
        frame: CGRect,
        hoverArmed: Bool,
        showsNowPlaying: Bool,
        showsHUD: Bool,
        showsControls: Bool,
        hudIndicatorStyle: HUDIndicatorStyle,
        invokeZone: CGRect?
    ) {
        appliedFrames.append(frame)
        hoverArmedStates.append(hoverArmed)
        showsNowPlayingStates.append(showsNowPlaying)
        showsHUDStates.append(showsHUD)
        showsControlsStates.append(showsControls)
        hudIndicatorStyleStates.append(hudIndicatorStyle)
        invokeZones.append(invokeZone)
    }

    func close() {
        closed = true
    }
}

/// Factory double: hands out RecordingPanels and remembers what was created.
@MainActor
final class PanelRecorder {
    private(set) var created: [(screen: ScreenDescription, style: Style, panel: RecordingPanel)] = []

    func make(_ screen: ScreenDescription, _ style: Style) -> RecordingPanel {
        let panel = RecordingPanel()
        created.append((screen, style, panel))
        return panel
    }

    /// The most recent panel created for a display (recreation replaces it).
    func panel(for id: DisplayUUID) -> RecordingPanel? {
        created.last(where: { $0.screen.id == id })?.panel
    }
}
