import Foundation
import Testing
@testable import Crema

/// The stale-display-ID regression: DisplayServices Get/SetBrightness take a
/// CGDisplayID, and those IDs are not stable across display sleep/wake and
/// reconfiguration. A bridge that froze the ID at init rots the whole
/// brightness path the first time the main display is re-enumerated (restart
/// cured it, a toggle did not). The fix re-resolves the ID per operation.
///
/// The real Get/SetBrightness are faked through the injectable symbol resolver
/// — no private API is touched. C function pointers cannot capture context, so
/// the fake's state lives in a file global; the suite is serialized so parallel
/// tests never share it.
@Suite(.serialized)
struct DisplayServicesBridgeDisplayIDTests {

    @Test func perOperationResolutionSurvivesADisplayIDChange() {
        fakeDisplay.reset(validID: 2, currentID: 2, brightness: 0.4)
        // The provider models CGMainDisplayID() — it reports the current main
        // display, which moves when the configuration changes.
        let bridge = DisplayServicesBridge(
            displayProvider: { fakeDisplay.currentID },
            resolver: fakeResolver
        )
        #expect(bridge.read() == 0.4)

        // Reconfiguration: the old main-display ID (2) retires, a new one (5)
        // becomes current. A launch-frozen ID would now be stale and fail.
        fakeDisplay.reconfigure(validID: 5, currentID: 5)

        // Re-resolved each op, so the same bridge instance keeps working — no
        // relaunch, no recreation.
        #expect(bridge.read() == 0.4)
        #expect(bridge.write(0.7))
        #expect(bridge.read() == 0.7)
    }

    @Test func aFrozenDisplayIDReproducesTheStaleIDDeath() {
        // The pre-fix behavior, modeled by a constant provider: once the valid
        // ID moves, every read and write fails and the brightness path is dead
        // until relaunch. This is the released-v1.1.0 bug in one assertion.
        fakeDisplay.reset(validID: 2, currentID: 2, brightness: 0.4)
        let frozen = DisplayServicesBridge(displayProvider: { 2 }, resolver: fakeResolver)
        #expect(frozen.read() == 0.4)

        fakeDisplay.reconfigure(validID: 5, currentID: 5)
        #expect(frozen.read() == nil)        // stale ID → unreadable
        #expect(frozen.write(0.7) == false)  // stale ID → write refused
    }
}

// MARK: - Faked DisplayServices border

private typealias GetC = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias SetC = @convention(c) (UInt32, Float) -> Int32

/// Mirrors the private API's contract: Get/SetBrightness succeed (return 0) only
/// for the currently valid display ID, and fail (non-zero) for any other —
/// exactly how a stale ID behaves against the live framework.
private final class FakeDisplayState: @unchecked Sendable {
    private let lock = NSLock()
    private var _validID: UInt32 = 1
    private var _currentID: UInt32 = 1
    private var _brightness: Float = 0.5

    var currentID: UInt32 { lock.withLock { _currentID } }

    func reset(validID: UInt32, currentID: UInt32, brightness: Float) {
        lock.withLock {
            _validID = validID
            _currentID = currentID
            _brightness = brightness
        }
    }

    func reconfigure(validID: UInt32, currentID: UInt32) {
        lock.withLock {
            _validID = validID
            _currentID = currentID
        }
    }

    func get(_ display: UInt32, into out: UnsafeMutablePointer<Float>) -> Int32 {
        lock.withLock {
            guard display == _validID else { return 1 }
            out.pointee = _brightness
            return 0
        }
    }

    func set(_ display: UInt32, to value: Float) -> Int32 {
        lock.withLock {
            guard display == _validID else { return 1 }
            _brightness = value
            return 0
        }
    }
}

private nonisolated(unsafe) let fakeDisplay = FakeDisplayState()

private func fakeGet(_ display: UInt32, _ out: UnsafeMutablePointer<Float>) -> Int32 {
    fakeDisplay.get(display, into: out)
}

private func fakeSet(_ display: UInt32, _ value: Float) -> Int32 {
    fakeDisplay.set(display, to: value)
}

private func fakeResolver(_ name: String) -> UnsafeMutableRawPointer? {
    switch name {
    case "DisplayServicesGetBrightness":
        unsafeBitCast(fakeGet as GetC, to: UnsafeMutableRawPointer.self)
    case "DisplayServicesSetBrightness":
        unsafeBitCast(fakeSet as SetC, to: UnsafeMutableRawPointer.self)
    default:
        nil
    }
}
