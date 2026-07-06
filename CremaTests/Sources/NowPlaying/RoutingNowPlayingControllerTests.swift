import Foundation
import Testing
@testable import Crema

/// The routing controller sends commands to the active channel (the same
/// backend as the active source), resolved per command; throws when none.
struct RoutingNowPlayingControllerTests {

    @Test func routesCommandsToTheActiveChannel() async throws {
        let channel = MockCommandChannel()
        let controller = RoutingNowPlayingController(activeChannel: { channel })

        try await controller.togglePlayPause()
        try await controller.seek(to: 30)

        #expect(channel.commands == [.togglePlayPause, .seek(30)])
    }

    @Test func followsTheActiveChannelWhenItSwitches() async throws {
        let adapter = MockCommandChannel()
        let jxa = MockCommandChannel()
        let active = LockedChannel(adapter)
        let controller = RoutingNowPlayingController(activeChannel: { active.value })

        try await controller.togglePlayPause()   // adapter active
        active.value = jxa                        // chain fell back
        try await controller.seek(to: 5)          // now via JXA

        #expect(adapter.commands == [.togglePlayPause])
        #expect(jxa.commands == [.seek(5)])
    }

    @Test func throwsWhenNoChannelIsActive() async {
        let controller = RoutingNowPlayingController(activeChannel: { nil })
        await #expect(throws: NowPlayingCommandError.self) {
            try await controller.togglePlayPause()
        }
    }

    @Test func propagatesChannelFailure() async {
        let channel = MockCommandChannel()
        channel.shouldThrow = true
        let controller = RoutingNowPlayingController(activeChannel: { channel })
        await #expect(throws: (any Error).self) {
            try await controller.togglePlayPause()
        }
    }

    /// Small lock box so the test can swap the active channel across awaits.
    private final class LockedChannel: @unchecked Sendable {
        private let lock = NSLock()
        private var channel: MockCommandChannel
        init(_ channel: MockCommandChannel) { self.channel = channel }
        var value: MockCommandChannel {
            get { lock.withLock { channel } }
            set { lock.withLock { channel = newValue } }
        }
    }
}
