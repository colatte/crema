import Foundation
@testable import Crema

/// Test fake: permission state controlled by the test; records requests.
/// Lock-protected — callable from any isolation.
final class MockAccessibilityPermission: AccessibilityPermission, @unchecked Sendable {
    private let lock = NSLock()
    private var _granted: Bool
    private var _requestCount = 0
    private var _mainThreadChecks = 0

    var granted: Bool {
        get { lock.withLock { _granted } }
        set { lock.withLock { _granted = newValue } }
    }

    var requestCount: Int { lock.withLock { _requestCount } }
    /// How many `isGranted()` reads landed on the MAIN thread. `AXIsProcessTrusted`
    /// is a blocking TCC round-trip, so a periodic reader (the tap's 2 s health
    /// poll) keeps it off the main thread; only the rare tick that actually
    /// reconfigures the port pays for it there.
    /// (docs/DECISIONS.md: tap-mutation-on-its-own-thread)
    var mainThreadChecks: Int { lock.withLock { _mainThreadChecks } }

    init(granted: Bool = false) {
        _granted = granted
    }

    func isGranted() -> Bool {
        let onMain = Thread.isMainThread
        return lock.withLock {
            if onMain { _mainThreadChecks += 1 }
            return _granted
        }
    }

    func requestAccess() {
        lock.withLock { _requestCount += 1 }
    }
}
