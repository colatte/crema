import Foundation
@testable import Crema

/// Test fake for the brightness backend (one shape serves screen and keyboard,
/// like the protocol): the test drives value and availability; records writes.
/// Lets the source/controller logic run without the real API.
/// `writeSucceeds` decouples the write result from availability so the
/// apply-and-verify failure path (available, but the write does not take) is
/// reachable; nil keeps the natural "succeeds while available" behavior.
final class FakeBrightnessBackend: BrightnessBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float?
    private var _available: Bool
    private var _writeSucceeds: Bool?
    private var _writes: [Float] = []

    init(available: Bool = true, value: Float? = 0.5, writeSucceeds: Bool? = nil) {
        _available = available
        _value = value
        _writeSucceeds = writeSucceeds
    }

    var isAvailable: Bool { lock.withLock { _available } }
    var value: Float? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    var writes: [Float] { lock.withLock { _writes } }

    func read() -> Float? { value }

    func write(_ value: Float) -> Bool {
        lock.withLock {
            _writes.append(value)
            _value = value
            return _writeSucceeds ?? _available
        }
    }
}
