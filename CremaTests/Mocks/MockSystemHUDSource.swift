import Foundation
@testable import Crema

/// Test fake: the test drives the stream via `emit`/`finish` and controls
/// availability. Lock-protected, so it is safe to drive from the test while
/// the @MainActor Coordinator consumes it.
final class MockSystemHUDSource: SystemHUDSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let lock = NSLock()
    private var _available: Bool

    var available: Bool {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }

    init(available: Bool = true) {
        _available = available
        var continuation: AsyncStream<SystemHUD>.Continuation!
        self.updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func isAvailable() async -> Bool { available }

    func emit(_ value: SystemHUD) { continuation.yield(value) }
    func finish() { continuation.finish() }
}
