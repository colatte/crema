import Testing
@testable import Crema

/// The launch-at-login contract the Settings toggle relies on: enabling
/// registers, disabling unregisters, and a failed registration leaves the real
/// status unchanged (so the toggle can snap back instead of persisting a wish
/// that did not take).
@MainActor
struct LoginItemTests {

    @Test func startsFromTheGivenStatus() {
        #expect(!MockLoginItem().isEnabled)
        #expect(MockLoginItem(enabled: true).isEnabled)
    }

    @Test func setEnabledFlipsTheStatus() throws {
        let item = MockLoginItem()
        try item.setEnabled(true)
        #expect(item.isEnabled)
        try item.setEnabled(false)
        #expect(!item.isEnabled)
    }

    @Test func aFailedRegistrationLeavesTheStatusUnchanged() {
        let item = MockLoginItem()
        item.failOnSet = true
        #expect(throws: MockLoginItem.Failure.self) { try item.setEnabled(true) }
        #expect(!item.isEnabled)
        #expect(!item.requiresApproval)
    }

    @Test func aRegistrationNeedingApprovalIsNotYetEnabled() throws {
        // The distinction the toggle relies on: register succeeded but the
        // item still needs approval, so isEnabled stays false.
        let item = MockLoginItem()
        item.enableRequiresApproval = true
        try item.setEnabled(true)
        #expect(!item.isEnabled)
        #expect(item.requiresApproval)
    }
}
