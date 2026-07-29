import ServiceManagement
import Testing
@testable import Crema

/// The real login item's own wiring — the half a fake can never speak for.
///
/// Every other login-item test drives `MockLoginItem`, which proves the app's
/// DECISIONS are right and says nothing about whether the type that talks to
/// macOS maps them correctly. A mutation swapping the two service calls (so
/// turning "open at login" ON unregisters the app) left the whole suite green:
/// exactly the failure the author hit in the wild, and nothing would have caught
/// it. These are the tests that would.
@MainActor
struct SMAppServiceLoginItemTests {

    private final class Calls {
        var registered = 0
        var unregistered = 0
    }

    private func item(_ calls: Calls, status: SMAppService.Status = .notFound) -> SMAppServiceLoginItem {
        SMAppServiceLoginItem(
            readStatus: { status },
            register: { calls.registered += 1 },
            unregister: { calls.unregistered += 1 }
        )
    }

    @Test func turningItOnRegisters() {
        let calls = Calls()
        try? item(calls).setEnabled(true)
        #expect(calls.registered == 1)
        #expect(calls.unregistered == 0)
    }

    @Test func turningItOffUnregisters() {
        let calls = Calls()
        try? item(calls).setEnabled(false)
        #expect(calls.unregistered == 1)
        #expect(calls.registered == 0)
    }

    @Test func aFailedRegistrationReachesTheCaller() throws {
        // The menu's one-click repair and the Settings toggle both decide what to
        // show from whether this threw; swallowing it would report success.
        struct Denied: Error {}
        let item = SMAppServiceLoginItem(
            readStatus: { .notFound },
            register: { throw Denied() },
            unregister: {}
        )
        #expect(throws: Denied.self) { try item.setEnabled(true) }
    }

    @Test func approvalPendingIsNotReadAsOn() {
        // A non-throwing register() can land here, and reading it as enabled
        // would leave the toggle claiming something macOS has not granted.
        let calls = Calls()
        #expect(item(calls, status: .requiresApproval).status == .requiresApproval)
        #expect(item(calls, status: .requiresApproval).isEnabled == false)
    }

    @Test func everyOtherServiceStateIsNoRegistration() {
        // "No record" and "a record we cannot see" drive the same decisions, so
        // they collapse — but `.enabled` must never collapse with them.
        let calls = Calls()
        #expect(item(calls, status: .enabled).status == .enabled)
        #expect(item(calls, status: .notFound).status == .notRegistered)
        #expect(item(calls, status: .notRegistered).status == .notRegistered)
    }
}
