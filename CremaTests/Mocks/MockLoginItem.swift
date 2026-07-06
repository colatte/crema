@testable import Crema

/// Test double for the launch-at-login control: records the wish, and can be
/// told to fail registration so the Settings toggle's revert path is testable.
@MainActor
final class MockLoginItem: LoginItemManaging {
    private(set) var isEnabled: Bool
    private(set) var requiresApproval: Bool
    var failOnSet = false
    /// When set, `setEnabled(true)` succeeds but lands in the pending-approval
    /// state (mirrors a non-throwing SMAppService.register that needs approval).
    var enableRequiresApproval = false
    struct Failure: Error {}

    init(enabled: Bool = false, requiresApproval: Bool = false) {
        isEnabled = enabled
        self.requiresApproval = requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if failOnSet { throw Failure() }
        if enabled, enableRequiresApproval {
            isEnabled = false
            requiresApproval = true
        } else {
            isEnabled = enabled
            requiresApproval = false
        }
    }
}
