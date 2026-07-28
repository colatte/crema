import Foundation
@testable import Crema

/// Test fake: the test drives the stream via `emit`/`finish` and controls
/// availability. Lock-protected, so it is safe to drive from the test while
/// the @MainActor Coordinator consumes it. Stoppable like the real sources, so
/// the chain's promotion path (which stops a silent source to force a cutover)
/// can be exercised with mocks.
final class MockNowPlayingSource: NowPlayingSource, StoppableSource, @unchecked Sendable {
    let updates: AsyncStream<NowPlaying>

    private let continuation: AsyncStream<NowPlaying>.Continuation
    private let lock = NSLock()
    private var _available: Bool
    private var _seeks: [Double] = []
    private var _seekFailures = 0

    var available: Bool {
        get { lock.withLock { _available } }
        set { lock.withLock { _available = newValue } }
    }

    /// Every noteSeek target, in order — pins that the Coordinator's scrub
    /// hints the source (overriding the protocol's no-op default).
    var seeks: [Double] { lock.withLock { _seeks } }
    /// How many failed-seek rollbacks the Coordinator reported.
    var seekFailures: Int { lock.withLock { _seekFailures } }

    func noteSeek(to seconds: Double) {
        lock.withLock { _seeks.append(seconds) }
    }

    func noteSeekFailed() {
        lock.withLock { _seekFailures += 1 }
    }

    init(available: Bool = true) {
        _available = available
        var continuation: AsyncStream<NowPlaying>.Continuation!
        self.updates = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func isAvailable() async -> Bool { available }

    func emit(_ value: NowPlaying) { continuation.yield(value) }
    func finish() { continuation.finish() }
    func stop() { continuation.finish() }
}
