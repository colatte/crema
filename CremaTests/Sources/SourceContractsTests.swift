import Testing
@testable import Crema

struct SourceContractsTests {

    // MARK: - Sources: streams driven by the test

    @Test func mockNowPlayingSourceEmitsUpdatesInOrder() async {
        let source = MockNowPlayingSource()
        let first = NowPlaying(title: "One", isPlaying: true, position: 0, duration: 60)
        let second = NowPlaying(title: "Two", isPlaying: false, position: 10, duration: 60)

        var iterator = source.updates.makeAsyncIterator()
        source.emit(first)
        source.emit(second)

        #expect(await iterator.next() == first)
        #expect(await iterator.next() == second)
    }

    @Test func mockNowPlayingSourceFinishEndsTheStream() async {
        let source = MockNowPlayingSource()
        var iterator = source.updates.makeAsyncIterator()
        source.finish()
        #expect(await iterator.next() == nil)
    }

    @Test func mockSystemHUDSourceEmitsUpdates() async {
        let source = MockSystemHUDSource()
        let hud = SystemHUD(kind: .volume, value: 0.25)

        var iterator = source.updates.makeAsyncIterator()
        source.emit(hud)

        #expect(await iterator.next() == hud)
    }

    @Test func mockSourcesReportTestControlledAvailability() async {
        #expect(await MockNowPlayingSource(available: true).isAvailable())
        #expect(await !MockNowPlayingSource(available: false).isAvailable())
        #expect(await MockSystemHUDSource(available: true).isAvailable())
        #expect(await !MockSystemHUDSource(available: false).isAvailable())
    }

    // MARK: - Actuators: commands recorded in order

    @Test func mockNowPlayingControllerRecordsMediaCommands() async throws {
        let controller = MockNowPlayingController()

        try await controller.togglePlayPause()
        try await controller.seek(to: 30)

        #expect(controller.commands == [.togglePlayPause, .seek(seconds: 30)])
    }

    @Test func mockVolumeControllerRecordsAdjustments() async throws {
        let controller = MockVolumeController()
        let external = DisplayUUID(rawValue: "37D8832A-2D66-02CA-B9F7-8F30A301B230")

        try await controller.setVolume(0.7, on: nil)
        try await controller.setVolume(0.2, on: external)
        try await controller.setMuted(true, on: nil)

        #expect(controller.commands == [
            .setVolume(0.7, display: nil),
            .setVolume(0.2, display: external),
            .setMuted(true, display: nil),
        ])
    }

    @Test func mockScreenBrightnessControllerRecordsAdjustments() async throws {
        let controller = MockScreenBrightnessController()

        try await controller.setBrightness(0.9, on: nil)

        #expect(controller.commands == [.setBrightness(0.9, display: nil)])
    }

    @Test func mockKeyboardBrightnessControllerRecordsAdjustments() async throws {
        let controller = MockKeyboardBrightnessController()

        try await controller.setBrightness(0.3)

        #expect(controller.commands == [.setBrightness(0.3)])
    }
}
