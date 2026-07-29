import Foundation
import Testing
@testable import Crema

/// The stale-keyboard-ID sibling of the display bridge's regression
/// (docs/DECISIONS.md: J2-display-id-stale): backlight IDs are enumerated from
/// the client's connection, and a bridge that froze the ID at init would rot
/// the keyboard-brightness path the first time the enumeration moved. The fix
/// re-resolves the ID per operation, exactly like the display bridge.
///
/// The private client is faked through the injectable class resolver — no
/// private API is touched. The bridge instantiates the class itself, so the
/// fake's state lives in a file global; the suite is serialized so parallel
/// tests never share it.
@Suite(.serialized)
struct CoreBrightnessKeyboardBridgeKeyboardIDTests {

    @Test func perOperationResolutionSurvivesAKeyboardIDChange() {
        fakeKeyboard.reset(validID: 2, brightness: 0.4)
        let bridge = CoreBrightnessKeyboardBridge(resolver: fakeClassResolver)
        #expect(bridge.read() == 0.4)

        // Re-enumeration: the old backlight ID (2) retires, a new one (5)
        // becomes the built-in. A launch-frozen ID would now be stale and fail.
        fakeKeyboard.reconfigure(validID: 5)

        // Re-resolved each op, so the same bridge instance keeps working — no
        // relaunch, no recreation.
        #expect(bridge.read() == 0.4)
        #expect(bridge.write(0.7))
        #expect(bridge.read() == 0.7)
    }

    @Test func aFrozenKeyboardIDReproducesTheStaleIDDeath() {
        // The pre-parity behavior, modeled by a constant provider: once the
        // valid ID moves, every read and write fails and the keyboard path is
        // dead until relaunch — the display bridge's released bug, on this arm.
        fakeKeyboard.reset(validID: 2, brightness: 0.4)
        let frozen = CoreBrightnessKeyboardBridge(
            resolver: fakeClassResolver,
            keyboardIDProvider: { 2 }
        )
        #expect(frozen.read() == 0.4)

        fakeKeyboard.reconfigure(validID: 5)
        #expect(frozen.read() == nil)        // stale ID → unreadable
        #expect(frozen.write(0.7) == false)  // stale ID → write refused
    }
}

// MARK: - Faked KeyboardBrightnessClient border

/// Mirrors the private API's contract: brightness reads return a negative value
/// and writes return false for any ID that is not the currently valid one —
/// exactly how a stale ID behaves against the live client.
private final class FakeKeyboardState: @unchecked Sendable {
    private let lock = NSLock()
    private var _validID: UInt64 = 1
    private var _brightness: Float = 0.5

    // The enumeration always carries a non-built-in extra (an external
    // keyboard) so the built-in filter is exercised, not bypassed.
    var ids: [NSNumber] { lock.withLock { [NSNumber(value: _validID), NSNumber(value: 99)] } }

    func reset(validID: UInt64, brightness: Float) {
        lock.withLock {
            _validID = validID
            _brightness = brightness
        }
    }

    func reconfigure(validID: UInt64) {
        lock.withLock { _validID = validID }
    }

    func isBuiltIn(_ id: UInt64) -> Bool {
        lock.withLock { id == _validID }
    }

    func brightness(for id: UInt64) -> Float {
        lock.withLock { id == _validID ? _brightness : -1 }
    }

    func setBrightness(_ value: Float, for id: UInt64) -> Bool {
        lock.withLock {
            guard id == _validID else { return false }
            _brightness = value
            return true
        }
    }
}

private nonisolated(unsafe) let fakeKeyboard = FakeKeyboardState()

private final class FakeKeyboardBrightnessClient: NSObject {
    @objc(brightnessForKeyboard:)
    func brightness(forKeyboard id: UInt64) -> Float {
        fakeKeyboard.brightness(for: id)
    }

    @objc(setBrightness:forKeyboard:)
    func setBrightness(_ value: Float, forKeyboard id: UInt64) -> Bool {
        fakeKeyboard.setBrightness(value, for: id)
    }

    @objc(copyKeyboardBacklightIDs)
    func copyKeyboardBacklightIDs() -> NSArray {
        fakeKeyboard.ids as NSArray
    }

    @objc(isKeyboardBuiltIn:)
    func isKeyboardBuiltIn(_ id: UInt64) -> Bool {
        fakeKeyboard.isBuiltIn(id)
    }
}

private func fakeClassResolver(_ name: String) -> AnyClass? {
    name == "KeyboardBrightnessClient" ? FakeKeyboardBrightnessClient.self : nil
}
