import Foundation
@testable import Crema

/// Test fake: records every screen-brightness adjustment it receives, in order.
/// Lock-protected — callable from any isolation (e.g. the @MainActor Coordinator).
final class MockScreenBrightnessController: ScreenBrightnessController, @unchecked Sendable {
    enum Command: Equatable {
        case setBrightness(Double, display: DisplayUUID?)
    }

    struct Refusal: Error {}

    private let lock = NSLock()
    private var recorded: [Command] = []
    private var refusing = false

    var commands: [Command] { lock.withLock { recorded } }

    /// Makes every later write throw — a neighbour that stopped answering, or a
    /// backend that lost its display.
    func refuseEverything() {
        lock.withLock { refusing = true }
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws {
        let refuse = lock.withLock {
            recorded.append(.setBrightness(value, display: display))
            return refusing
        }
        if refuse { throw Refusal() }
    }
}
