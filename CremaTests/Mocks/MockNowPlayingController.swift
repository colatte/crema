import Foundation
@testable import Crema

/// Test fake: records every media command it receives, in order.
/// Lock-protected — callable from any isolation (e.g. the @MainActor Coordinator).
final class MockNowPlayingController: NowPlayingController, @unchecked Sendable {
    enum Command: Equatable {
        case togglePlayPause
        case seek(seconds: Double)
        case nextTrack
        case previousTrack
    }

    struct Failure: Error {}

    private let lock = NSLock()
    private var recorded: [Command] = []
    private var _shouldThrow = false
    private var _errorToThrow: Error?
    private var _failingSeekSeconds: Double?

    var commands: [Command] { lock.withLock { recorded } }
    /// When true, commands are recorded but then throw a default Failure —
    /// simulates a blocked write path so degradation can be tested.
    var shouldThrow: Bool {
        get { lock.withLock { _shouldThrow } }
        set { lock.withLock { _shouldThrow = newValue } }
    }

    /// A specific error to throw (takes precedence) — e.g. a transient
    /// NowPlayingCommandError.noActiveSource.
    var errorToThrow: Error? {
        get { lock.withLock { _errorToThrow } }
        set { lock.withLock { _errorToThrow = newValue } }
    }

    /// Fails only the seek whose target matches — lets a test race one stale
    /// failing seek against a newer scrub whose own command succeeds.
    var failingSeekSeconds: Double? {
        get { lock.withLock { _failingSeekSeconds } }
        set { lock.withLock { _failingSeekSeconds = newValue } }
    }

    func togglePlayPause() async throws { try record(.togglePlayPause) }
    func seek(to seconds: Double) async throws { try record(.seek(seconds: seconds)) }
    func nextTrack() async throws { try record(.nextTrack) }
    func previousTrack() async throws { try record(.previousTrack) }

    private func record(_ command: Command) throws {
        try lock.withLock {
            recorded.append(command)
            if let error = _errorToThrow { throw error }
            if _shouldThrow { throw Failure() }
            if case .seek(let seconds) = command, seconds == _failingSeekSeconds { throw Failure() }
        }
    }
}
