import Foundation
@testable import Crema

/// One double for all three drag actuators, whose FIRST write parks until the
/// test releases it while every later one returns at once: run concurrently, the
/// writes land out of order; run one after another, they land as asked. `started`
/// records each write as it begins, `landed` as it returns.
///
/// The park is the suite's bounded poll, never a continuation, and on the suite's
/// own budget (docs/TESTING.md): a release that never comes fails the test at its
/// next assertion instead of hanging the run.
final class HeldFirstWriteActuator: VolumeController, ScreenBrightnessController, KeyboardBrightnessController,
@unchecked Sendable {
    private let lock = NSLock()
    private var _started: [Double] = []
    private var _landed: [Double] = []
    private var released = false

    var started: [Double] { lock.withLock { _started } }
    var landed: [Double] { lock.withLock { _landed } }

    func release() {
        lock.withLock { released = true }
    }

    func setVolume(_ value: Double, on display: DisplayUUID?) async throws {
        await write(value)
    }

    func setMuted(_ muted: Bool, on display: DisplayUUID?) async throws {}

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        await write(value)
        return value
    }

    func setBrightness(_ value: Double) async throws {
        await write(value)
    }

    private func write(_ value: Double) async {
        let isFirst = lock.withLock {
            _started.append(value)
            return _started.count == 1
        }
        if isFirst {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: boundedWaitDeadline)
            while !lock.withLock({ released }), clock.now < deadline {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
        lock.withLock { _landed.append(value) }
    }
}
