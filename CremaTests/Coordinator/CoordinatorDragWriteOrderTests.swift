import Testing
@testable import Crema

/// A drag's frames land on each actuator in the order the finger produced them,
/// so the level the finger stopped at is the last one written. The double's
/// first write parks and the second returns at once: dispatched concurrently,
/// the second lands first and the first then overwrites it with a level the
/// finger already left.
@MainActor
struct CoordinatorDragWriteOrderTests {

    private func coordinator(writingTo actuator: HeldFirstWriteActuator) -> (Coordinator, MockSystemHUDSource) {
        let hudSource = MockSystemHUDSource()
        let coordinator = Coordinator(
            nowPlayingSource: MockNowPlayingSource(),
            systemHUDSource: hudSource,
            nowPlayingController: MockNowPlayingController(),
            volumeController: actuator,
            screenBrightnessController: actuator,
            keyboardBrightnessController: actuator,
            clock: TestSleepClock()
        )
        coordinator.start()
        return (coordinator, hudSource)
    }

    @Test(arguments: [SystemHUD.Kind.volume, .screenBrightness, .keyboardBrightness])
    func theLastFrameLandsLast(kind: SystemHUD.Kind) async throws {
        let actuator = HeldFirstWriteActuator()
        let (coordinator, hudSource) = coordinator(writingTo: actuator)
        hudSource.emit(SystemHUD(kind: kind, value: 0.5))
        try #require(await eventually { coordinator.layers.hud != nil })

        coordinator.hudSliderChanged(to: 0.3)
        coordinator.hudSliderChanged(to: 0.7)
        try #require(await eventuallyOffActor { actuator.started.first == 0.3 })
        // The newer frame waits for the one in flight instead of overtaking it.
        #expect(await !footprintAppears { actuator.started.count > 1 })

        actuator.release()

        #expect(await eventuallyOffActor { actuator.landed.count == 2 })
        #expect(actuator.landed == [0.3, 0.7])
    }
}
