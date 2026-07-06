import Foundation
@testable import Crema

/// Test fake: permission state controlled by the test; records requests.
/// Lock-protected — callable from any isolation.
final class MockAccessibilityPermission: AccessibilityPermission, @unchecked Sendable {
    private let lock = NSLock()
    private var _granted: Bool
    private var _requestCount = 0

    var granted: Bool {
        get { lock.withLock { _granted } }
        set { lock.withLock { _granted = newValue } }
    }

    var requestCount: Int { lock.withLock { _requestCount } }

    init(granted: Bool = false) {
        _granted = granted
    }

    func isGranted() -> Bool { granted }

    func requestAccess() {
        lock.withLock { _requestCount += 1 }
    }
}
