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
/// Env-scalable because the bound is a saturation guard, not a correctness
/// bound: on a 3-vCPU CI runner sharing one MainActor across 900-odd parallel
/// tests, fair-share alone pushed healthy multi-stage waits past 5 s (measured:
/// the same suites at 1.4 s on one run and 6 s per TEST on the next, after the
/// suite grew by ~250 tests). The CI workflow widens it via
/// TEST_RUNNER_CREMA_TEST_WAIT_SECONDS; locally the 5 s discipline stands.
let boundedWaitSeconds: Double = {
    if let raw = ProcessInfo.processInfo.environment["CREMA_TEST_WAIT_SECONDS"],
       let seconds = Double(raw), seconds > 0 {
        return seconds
    }
    return 5
}()

let boundedWaitDeadline: Duration = .seconds(boundedWaitSeconds)

let boundedWaitHotSpins = 2000

/// A stream iterator whose `next()` is bounded by the wall clock, because the
/// raw one is not: `await iterator.next()` on a stream that never emits parks
/// forever, and a parked test does not fail — it holds the whole suite until
/// an outer timeout kills the run with no name attached (measured on CI: two
/// suites never reported and the job died mute at the 30-minute limit; the
/// unbounded-continuation deadlock is the same class round1-a1-a3 already
/// ruled on). Timeout and upstream-finish both return nil, so the assertion
/// right after fails loud with the test's own name.
///
/// A pump task consumes the stream eagerly into a buffer; `next()` polls it
/// with the same micro-sleep idiom as `eventually` — no continuation is ever
/// parked without a deadline. Eager consumption means the SOURCE's buffering
/// policy stops dropping under a slow consumer, which is equivalent here: a
/// directly-parked `next()` also received every element the moment it yielded.
/// Single-consumer, like the iterator it replaces.
final class BoundedStreamIterator<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [Element] = []
    private var finished = false
    private var pump: Task<Void, Never>?

    init(_ stream: AsyncStream<Element>) {
        pump = Task { [weak self] in
            for await element in stream {
                guard let self else { return }
                self.lock.withLock { self.buffer.append(element) }
            }
            self?.lock.withLock { self?.finished = true }
        }
    }

    deinit { pump?.cancel() }

    func next() async -> Element? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: boundedWaitDeadline)
        var spins = 0
        while true {
            let (element, done): (Element?, Bool) = lock.withLock {
                (buffer.isEmpty ? nil : buffer.removeFirst(), finished)
            }
            if let element { return element }
            if done || clock.now >= deadline { return nil }
            spins += 1
            if spins < boundedWaitHotSpins {
                await Task.yield()
            } else {
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }
}

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
func eventuallyOffActor(_ condition: @Sendable () -> Bool) async -> Bool {
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

/// Isolated UserDefaults for one test instance; deinit empties the persistent
/// domain and unlinks its plist, and the first init of a process reaps the
/// residue earlier runs left in ~/Library/Preferences.
final class EphemeralDefaults: @unchecked Sendable {
    let suiteName = "CremaTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    // cfprefsd can re-materialize an emptied domain's plist MINUTES after the
    // deinit's unlink, client long dead (measured 2026-08-08: empty probe
    // plists with mtimes 2-7 min past process death — the probe's own 3-5 s
    // windows had said "absent"). Past runs' files are therefore reaped once
    // per process instead of trusted gone. Any CremaTests.* file is fair
    // game: names are per-instance UUIDs no run ever reuses, and unlinking a
    // LIVE domain's file loses nothing — reads go through cfprefsd's cache —
    // so even a concurrent suite run (isolated DerivedData) is unharmed.
    private static let reapStaleSuites: Void = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences")
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        )) ?? []
        for url in files
            where url.lastPathComponent.hasPrefix("CremaTests.") && url.pathExtension == "plist" {
            try? FileManager.default.removeItem(at: url)
        }
    }()

    init() {
        _ = Self.reapStaleSuites
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        // removePersistentDomain is documented over keys and values only and
        // leaves the plist file behind (measured 2026-08-08: 7,607 empty
        // CremaTests.*.plist accumulated with this deinit running; probe with
        // control in scripts/probes/remove-persistent-domain.swift). The
        // unlink kills the file in the common case; the late-reflush residue
        // it cannot reach is what reapStaleSuites exists for. Never add
        // synchronize() here: it schedules a flush of the emptied domain that
        // races the unlink and brings the empty file back sooner (probe C).
        // A test that never wrote has no file; try? covers that resting case.
        let plist = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suiteName).plist")
        try? FileManager.default.removeItem(at: plist)
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
