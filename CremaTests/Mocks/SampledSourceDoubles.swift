import Foundation
@testable import Crema

/// Records how many times it was sampled — for routing tests.
final class SpySampledSource: ManuallySampledSource, @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var sampleCount: Int { lock.withLock { _count } }

    func sample() { lock.withLock { _count += 1 } }
}

/// Both a HUD source and sampleable: emits a fixed SystemHUD each time it is
/// sampled — for the end-to-end key→HUD wiring test.
final class FakeSampledHUDSource: SystemHUDSource, ManuallySampledSource, @unchecked Sendable {
    let updates: AsyncStream<SystemHUD>

    private let continuation: AsyncStream<SystemHUD>.Continuation
    private let lock = NSLock()
    private var _next: SystemHUD

    init(emitting hud: SystemHUD) {
        _next = hud
        var continuation: AsyncStream<SystemHUD>.Continuation!
        updates = AsyncStream(bufferingPolicy: .bufferingNewest(4)) { continuation = $0 }
        self.continuation = continuation
    }

    var next: SystemHUD {
        get { lock.withLock { _next } }
        set { lock.withLock { _next = newValue } }
    }

    func isAvailable() async -> Bool { true }
    func sample() { continuation.yield(next) }
}
