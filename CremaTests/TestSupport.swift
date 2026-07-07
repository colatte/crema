import Foundation

// A few test helpers force-unwrap known-good values (e.g. UserDefaults(suiteName:)).
// swiftlint:disable force_unwrapping

/// Spins the main actor until `condition` holds, without ever really sleeping.
/// Returns the final evaluation so call sites can `#expect(await eventually { … })`.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<2000 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// Gives pending main-actor work a chance to run (for asserting that
/// something did not happen).
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
}

/// Isolated UserDefaults for one test instance; wipes its persistent domain on
/// deinit so test runs don't accumulate plists in ~/Library/Preferences.
final class EphemeralDefaults: @unchecked Sendable {
    let suiteName = "CremaTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Mutable flag that observation/onChange closures can safely capture.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}

// swiftlint:enable force_unwrapping
