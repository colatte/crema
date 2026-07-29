import ServiceManagement

/// The three states a login-item registration can really be in, in the app's own
/// vocabulary (SMAppService's `.notFound` collapses into `.notRegistered` — for
/// every decision the app makes, "no record" and "record we can't see" are the
/// same thing).
enum LoginItemStatus: Equatable {
    case enabled
    /// Registered, but macOS is waiting for the user to approve it in System
    /// Settings › General › Login Items — a non-throwing `register()` can land
    /// here, so the toggle must not read this as fully on.
    case requiresApproval
    case notRegistered
}

/// Launch-at-login control behind a protocol, so the Settings toggle's logic is
/// testable without touching the real SMAppService registration.
@MainActor
protocol LoginItemManaging {
    var status: LoginItemStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

extension LoginItemManaging {
    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }
}

/// SMAppService-backed login item — the modern API (no helper bundle, no
/// deprecated SMLoginItemSetEnabled). We never auto-register: the status just
/// reflects reality, so launch-at-login starts off until the user opts in. That
/// deliberately departs from on-by-default — silently adding a login item is
/// intrusive and surprising; the user turns it on in Settings, and the same rule
/// holds when macOS revokes an existing registration (docs/DECISIONS.md:
/// login-item-intent — the app then asks, it does not re-register itself).
@MainActor
struct SMAppServiceLoginItem: LoginItemManaging {
    var status: LoginItemStatus {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        default: .notRegistered
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
