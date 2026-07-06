import Foundation
@testable import Crema

/// Test fake: the test drives the key stream via `emit`; availability is
/// controllable. Lock-protected, safe to drive while a consumer reads it.
final class MockMediaKeySource: MediaKeySource, @unchecked Sendable {
    let updates: AsyncStream<MediaKey>

    private let continuation: AsyncStream<MediaKey>.Continuation
    private let lock = NSLock()
    private var _available: Bool

    init(available: Bool = true) {
        _available = available
        var continuation: AsyncStream<MediaKey>.Continuation!
        updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    var available: Bool {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }

    func isAvailable() async -> Bool { available }

    func emit(_ key: MediaKey) { continuation.yield(key) }
    func finish() { continuation.finish() }
}
