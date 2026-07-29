@testable import Crema

/// Test double for the launch-at-login control: records the wish, and can be
/// told to fail registration so the Settings toggle's revert path is testable.
/// `registerCount` is what pins the app's promise never to re-register on its
/// own — only an explicit user action may increment it.
@MainActor
final class MockLoginItem: LoginItemManaging {
    private(set) var status: LoginItemStatus
    private(set) var registerCount = 0
    var failOnSet = false
    /// When set, `setEnabled(true)` succeeds but lands in the pending-approval
    /// state (mirrors a non-throwing SMAppService.register that needs approval).
    var enableRequiresApproval = false
    struct Failure: Error {}

    init(status: LoginItemStatus = .notRegistered) {
        self.status = status
    }

    convenience init(enabled: Bool = false, requiresApproval: Bool = false) {
        self.init(status: enabled ? .enabled : (requiresApproval ? .requiresApproval : .notRegistered))
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled { registerCount += 1 }
        if failOnSet { throw Failure() }
        if enabled {
            status = enableRequiresApproval ? .requiresApproval : .enabled
        } else {
            status = .notRegistered
        }
    }
}
