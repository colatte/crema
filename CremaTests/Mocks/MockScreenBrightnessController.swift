import Foundation
@testable import Crema

/// Test fake: records every screen-brightness adjustment it receives, in order.
/// Lock-protected — callable from any isolation (e.g. the @MainActor Coordinator).
final class MockScreenBrightnessController: ScreenBrightnessController, @unchecked Sendable {
    enum Command: Equatable {
        case setBrightness(Double, display: DisplayUUID?)
    }

    private let lock = NSLock()
    private var recorded: [Command] = []

    var commands: [Command] { lock.withLock { recorded } }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws {
        lock.withLock { recorded.append(.setBrightness(value, display: display)) }
    }
}
