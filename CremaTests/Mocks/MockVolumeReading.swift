import Foundation
@testable import Crema

/// Test fake for the on-demand volume read: answers `reading`, counts the reads,
/// and, while `held`, keeps a read in flight so a test can land something ahead
/// of it. The hold is a bounded poll on the suite's own budget, never a parked
/// continuation (docs/TESTING.md). Lock-protected, callable from any isolation.
final class MockVolumeReading: VolumeReading, @unchecked Sendable {
    private let lock = NSLock()
    private var _reading: SystemHUD?
    private var _reads = 0
    private var _held = false

    init(reading: SystemHUD? = SystemHUD(kind: .volume, value: 0.4)) {
        _reading = reading
    }

    var reading: SystemHUD? {
        get { lock.withLock { _reading } }
        set { lock.withLock { _reading = newValue } }
    }

    var reads: Int { lock.withLock { _reads } }

    var held: Bool {
        get { lock.withLock { _held } }
        set { lock.withLock { _held = newValue } }
    }

    func currentVolume() async -> SystemHUD? {
        lock.withLock { _reads += 1 }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: boundedWaitDeadline)
        while held, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return reading
    }
}
