import Foundation
@testable import Crema

/// Test fake: records every keyboard-backlight adjustment it receives, in order.
/// Lock-protected — callable from any isolation (e.g. the @MainActor Coordinator).
final class MockKeyboardBrightnessController: KeyboardBrightnessController, @unchecked Sendable {
    enum Command: Equatable {
        case setBrightness(Double)
    }

    private let lock = NSLock()
    private var recorded: [Command] = []

    var commands: [Command] { lock.withLock { recorded } }

    func setBrightness(_ value: Double) async throws {
        lock.withLock { recorded.append(.setBrightness(value)) }
    }
}
