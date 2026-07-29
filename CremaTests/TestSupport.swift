import Foundation

// A few test helpers force-unwrap known-good values (e.g. UserDefaults(suiteName:)).
// swiftlint:disable force_unwrapping

/// How every bounded wait in the suite is bounded: by WALL CLOCK, never by a
/// yield count. A scheduler-slot budget starves on a saturated machine (at
/// parallel-suite cold start, real fixture progress outlived any yield count),
/// while wall time passes no matter who holds the CPU. Hot path: pure yields,
/// so a healthy wait resolves in microseconds. Starved path: 1 ms real sleeps
/// up to the deadline — the deliberate, narrow exception to "tests never
/// really sleep" (production timers stay on SleepClock; this is executor
/// backoff inside the wait helper, not timer synchronization), and sleeping
/// frees the actor/thread for exactly the starved tasks the condition waits
/// on. Still bounded: a genuine wedge fails loud, never hangs the suite.
let boundedWaitDeadline: Duration = .seconds(5)
let boundedWaitHotSpins = 2000

/// Spins the main actor until `condition` holds, bounded by wall clock (see
/// boundedWaitDeadline). Returns the final evaluation so call sites can
/// `#expect(await eventually { … })`.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: boundedWaitDeadline)
    var spins = 0
    while clock.now < deadline {
        if condition() { return true }
        spins += 1
        if spins < boundedWaitHotSpins {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
    return condition()
}

/// The off-actor sibling, for conditions flipped by NON-MainActor work (stream
/// consumer tasks, lock-protected sinks). Deliberately separate from
/// `eventually`: an off-actor yield loop hands slots to the global executor
/// while parked MainActor tasks starve (the TestSleepClock lesson), so waits
/// on MainActor progress must use `eventually` — and this one exists so the
/// distinction is a choice, not a private copy per suite. Same wall-clock
/// bound (see boundedWaitDeadline).
func eventuallyOffActor(_ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: boundedWaitDeadline)
    var spins = 0
    while clock.now < deadline {
        if condition() { return true }
        spins += 1
        if spins < boundedWaitHotSpins {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(1))
        }
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
