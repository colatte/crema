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
    private var reported: Double?

    var commands: [Command] { lock.withLock { recorded } }

    /// Makes every later write throw — a neighbour that stopped answering, or a
    /// backend that lost its display.
    func refuseEverything() {
        lock.withLock { refusing = true }
    }

    /// Back to accepting: lets a test put a SUCCESSFUL write after a failed one,
    /// which is the only ordered way to prove the failure produced no echo.
    func acceptEverything() {
        lock.withLock { refusing = false }
    }

    /// Makes every later write report a value OTHER than its argument — an actuator
    /// that coalesces, whose driving call keeps writing newer values and returns
    /// holding an old one. The real one does this by draining a queue; a double
    /// only has to produce the divergence, since what is under test above it is
    /// which of the two numbers gets echoed.
    func reportsWritten(_ value: Double) {
        lock.withLock { reported = value }
    }

    /// Returns what "went out": the argument, unless the test asked for a
    /// divergence. Recording still keeps the ARGUMENT, because that is what the
    /// caller asked this actuator to do.
    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        let (refuse, reported) = lock.withLock {
            recorded.append(.setBrightness(value, display: display))
            return (refusing, self.reported)
        }
        if refuse { throw Refusal() }
        return reported ?? value
    }
}
