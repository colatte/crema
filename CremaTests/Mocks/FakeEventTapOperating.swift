import CoreGraphics
import Foundation
@testable import Crema

/// Test fake for the CGEventTap border: records install/uninstall and lets a
/// test flip either the enabled flag (system disable) or the port's validity
/// (system invalidate) behind the source's back — the two distinct failure
/// modes the health-check must tell apart. Lock-protected — the source's poll
/// task and the test thread both touch it.
final class FakeEventTapOperating: EventTapOperating, @unchecked Sendable {
    /// The opaque token the source stores; identity distinguishes reinstalls.
    final class Token {}

    private let lock = NSLock()
    private var _token: Token?
    private var _enabled = false
    /// A freshly installed port is valid; an invalidated one is dead until the
    /// health-check reinstalls (unlike disable, no re-enable recovers it).
    private var _valid = false
    private var _installCount = 0
    private var _setEnabledCalls: [Bool] = []
    private var _userInfos: [UnsafeMutableRawPointer] = []
    private var _operations: [String] = []

    /// How many times a tap was installed (a revive must not increment this —
    /// re-enabling keeps the same port and its consumer wiring; a reinstall
    /// after an invalidation does increment).
    var installCount: Int { lock.withLock { _installCount } }
    /// Whether the currently installed tap is enabled.
    var isCurrentlyEnabled: Bool { lock.withLock { _enabled } }
    /// Whether a tap is installed at all.
    var isInstalled: Bool { lock.withLock { _token != nil } }
    /// The current opaque token, for asserting a reinstall minted a fresh one.
    var currentToken: Token? { lock.withLock { _token } }
    /// Every `setEnabled` argument in order (install's implicit enable excluded).
    var setEnabledCalls: [Bool] { lock.withLock { _setEnabledCalls } }
    /// The `userInfo` pointer of every install, in order. It is
    /// `Unmanaged.passUnretained(source)`, so identical pointers across a
    /// reinstall prove the fresh port routes back to the same source — and thus
    /// the same, unchanged `consumer`, which the callback reads dynamically.
    /// This is the by-construction pin that a reinstall never drops suppression.
    var installedUserInfos: [UnsafeMutableRawPointer] { lock.withLock { _userInfos } }
    /// Every install/uninstall in call order — pins a forced reinstall as a
    /// paired uninstall→install (old port torn down first, no orphan) rather
    /// than a bare re-create over a still-live port.
    var operations: [String] { lock.withLock { _operations } }

    /// Simulate the system disabling the tap without delivering a callback. The
    /// port stays valid, so the health-check revives it in place.
    func simulateSystemDisable() {
        lock.withLock { _enabled = false }
    }

    /// Simulate the system invalidating the mach port outright — dead
    /// permanently, no re-enable recovers it. The source's state still says
    /// "installed" until the health-check notices and reinstalls from scratch.
    func simulateSystemInvalidate() {
        lock.withLock { _valid = false }
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
            _valid = true
            _installCount += 1
            _userInfos.append(userInfo)
            _operations.append("install")
            return token
        }
    }

    func isEnabled(_ token: AnyObject) -> Bool {
        lock.withLock { (token as AnyObject) === _token && _enabled }
    }

    func isValid(_ token: AnyObject) -> Bool {
        lock.withLock { (token as AnyObject) === _token && _valid }
    }

    func setEnabled(_ token: AnyObject, _ enabled: Bool) {
        lock.withLock {
            _setEnabledCalls.append(enabled)
            if (token as AnyObject) === _token { _enabled = enabled }
        }
    }

    func uninstall(_ token: AnyObject) {
        lock.withLock {
            _operations.append("uninstall")
            if (token as AnyObject) === _token {
                _token = nil
                _enabled = false
                _valid = false
            }
        }
    }
}
