import Foundation
@testable import Crema

/// Test fake command channel: records commands, optionally throws.
final class MockCommandChannel: NowPlayingCommandChannel, @unchecked Sendable {
    enum Command: Equatable {
        case togglePlayPause
        case seek(Double)
        case nextTrack
        case previousTrack
    }

    struct Failure: Error {}

    private let lock = NSLock()
    private var recorded: [Command] = []
    private var _shouldThrow = false

    var commands: [Command] { lock.withLock { recorded } }
    var shouldThrow: Bool {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }

    func togglePlayPause() async throws {
        try lock.withLock { recorded.append(.togglePlayPause); if _shouldThrow { throw Failure() } }
    }

    func seek(to seconds: Double) async throws {
        try lock.withLock { recorded.append(.seek(seconds)); if _shouldThrow { throw Failure() } }
    }

    func nextTrack() async throws {
        try lock.withLock { recorded.append(.nextTrack); if _shouldThrow { throw Failure() } }
    }

    func previousTrack() async throws {
        try lock.withLock { recorded.append(.previousTrack); if _shouldThrow { throw Failure() } }
    }
}
