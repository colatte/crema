@testable import Crema

/// Builds a Coordinator wired entirely to mocks and starts consumption.
@MainActor
struct CoordinatorHarness {
    let nowPlayingSource = MockNowPlayingSource()
    let hudSource = MockSystemHUDSource()
    let media = MockNowPlayingController()
    let volume = MockVolumeController()
    let screen = MockScreenBrightnessController()
    let keyboard = MockKeyboardBrightnessController()
    /// The neighbour's actuator (BetterDisplay). Present only when a test asks
    /// for it, so every existing test keeps the single-actuator wiring it had.
    let external: MockScreenBrightnessController?
    let clock = TestSleepClock()
    let coordinator: Coordinator

    init(
        hudRevertDelay: Double = Coordinator.defaultHUDRevertDelay,
        nowPlayingLinger: Double = Coordinator.defaultNowPlayingLinger,
        invokedLinger: Double = Coordinator.defaultInvokedLinger,
        hoverIntentDelay: Double = Coordinator.defaultHoverIntentDelay,
        hoverOutDebounce: Double = Coordinator.defaultHoverOutDebounce,
        scrubGraceWindow: Double = ScrubGrace.defaultWindow,
        scrubConfirmTolerance: Double = ScrubGrace.defaultConfirmTolerance,
        ignoresBrowserMedia: Bool = true,
        reactiveNowPlaying: Bool = true,
        withExternalBrightness: Bool = false
    ) {
        external = withExternalBrightness ? MockScreenBrightnessController() : nil
        coordinator = Coordinator(
            nowPlayingSource: nowPlayingSource,
            systemHUDSource: hudSource,
            nowPlayingController: media,
            volumeController: volume,
            screenBrightnessController: screen,
            keyboardBrightnessController: keyboard,
            externalScreenBrightnessController: external,
            clock: clock,
            hudRevertDelay: hudRevertDelay,
            nowPlayingLinger: nowPlayingLinger,
            invokedLinger: invokedLinger,
            hoverIntentDelay: hoverIntentDelay,
            hoverOutDebounce: hoverOutDebounce,
            scrubGraceWindow: scrubGraceWindow,
            scrubConfirmTolerance: scrubConfirmTolerance,
            ignoresBrowserMedia: ignoresBrowserMedia,
            reactiveNowPlaying: reactiveNowPlaying
        )
        coordinator.start()
    }

    static func playingTrack(
        title: String = "Breathe",
        position: Double = 10,
        isPlaying: Bool = true
    ) -> NowPlaying {
        NowPlaying(title: title, artist: "Pink Floyd", isPlaying: isPlaying, position: position, duration: 169)
    }
}
