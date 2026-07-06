import ServiceManagement

/// Launch-at-login control behind a protocol, so the Settings toggle's logic is
/// testable without touching the real SMAppService registration.
@MainActor
protocol LoginItemManaging {
    var isEnabled: Bool { get }
    /// Registered but waiting for the user to approve it in System Settings ›
    /// General › Login Items — a non-throwing `register()` can land here, so the
    /// toggle must not read this as fully on.
    var requiresApproval: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// SMAppService-backed login item — the modern API (no helper bundle, no
/// deprecated SMLoginItemSetEnabled). We never auto-register: `isEnabled` just
/// reflects the real status, so launch-at-login starts off until the user opts
/// in. That deliberately departs from on-by-default — silently
/// adding a login item on first run is intrusive and surprising; the user turns
/// it on in Settings.
@MainActor
struct SMAppServiceLoginItem: LoginItemManaging {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
