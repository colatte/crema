import Foundation
@testable import Crema

/// Test fake: records every volume adjustment it receives, in order.
/// Lock-protected — callable from any isolation (e.g. the @MainActor Coordinator).
final class MockVolumeController: VolumeController, @unchecked Sendable {
    enum Command: Equatable {
        case setVolume(Double, display: DisplayUUID?)
        case setMuted(Bool, display: DisplayUUID?)
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

    func setVolume(_ value: Double, on display: DisplayUUID?) async throws {
        try lock.withLock { recorded.append(.setVolume(value, display: display)); if _shouldThrow { throw Failure() } }
    }

    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws {
        try lock.withLock { recorded.append(.setMuted(muted, display: display)); if _shouldThrow { throw Failure() } }
    }
}
