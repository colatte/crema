import CoreGraphics
import Foundation
@testable import Crema

/// Test fake for the CGEventTap border: records install/uninstall and lets a
/// test flip the enabled flag to simulate the system disabling the tap behind
/// the source's back (secure-input transitions, timeouts). Lock-protected — the
/// source's poll task and the test thread both touch it.
final class FakeEventTapOperating: EventTapOperating, @unchecked Sendable {
    /// The opaque token the source stores; identity distinguishes reinstalls.
    final class Token {}

    private let lock = NSLock()
    private var _token: Token?
    private var _enabled = false
    private var _installCount = 0
    private var _setEnabledCalls: [Bool] = []

    /// How many times a tap was installed (a revive must not increment this —
    /// re-enabling keeps the same port and its consumer wiring).
    var installCount: Int { lock.withLock { _installCount } }
    /// Whether the currently installed tap is enabled.
    var isCurrentlyEnabled: Bool { lock.withLock { _enabled } }
    /// Whether a tap is installed at all.
    var isInstalled: Bool { lock.withLock { _token != nil } }
    /// Every `setEnabled` argument in order (install's implicit enable excluded).
    var setEnabledCalls: [Bool] { lock.withLock { _setEnabledCalls } }

    /// Simulate the system disabling the tap without delivering a callback.
    func simulateSystemDisable() {
        lock.withLock { _enabled = false }
    }

    func install(
        mask: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer
    ) -> AnyObject? {
        lock.withLock {
            let token = Token()
            _token = token
            _enabled = true
            _installCount += 1
            return token
        }
    }

    func isEnabled(_ token: AnyObject) -> Bool {
        lock.withLock { (token as AnyObject) === _token && _enabled }
    }

    func setEnabled(_ token: AnyObject, _ enabled: Bool) {
        lock.withLock {
            _setEnabledCalls.append(enabled)
            if (token as AnyObject) === _token { _enabled = enabled }
        }
    }

    func uninstall(_ token: AnyObject) {
        lock.withLock {
            if (token as AnyObject) === _token {
                _token = nil
                _enabled = false
            }
        }
    }
}
