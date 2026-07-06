import Foundation
@testable import Crema

/// Test fake for the screen backend: the test drives value and availability;
/// records writes. Lets the source/controller logic run without the real API.
final class FakeScreenBrightnessBackend: ScreenBrightnessBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float?
    private var _available: Bool
    private var _writes: [Float] = []

    init(available: Bool = true, value: Float? = 0.5) {
        _available = available
        _value = value
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
            return _available
        }
    }
}

/// Test fake for the keyboard backend — same shape.
final class FakeKeyboardBrightnessBackend: KeyboardBrightnessBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float?
    private var _available: Bool
    private var _writes: [Float] = []

    init(available: Bool = true, value: Float? = 0.5) {
        _available = available
        _value = value
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
            return _available
        }
    }
}
