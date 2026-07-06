import Foundation

/// A wall clock the test moves by hand, for sources that compare against `now()`
/// (e.g. the screen-brightness key-activity window). Separate from
/// TestSleepClock, which drives poll cadence, not timestamps.
final class ManualNow: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ start: Date = Date(timeIntervalSince1970: 1_000)) {
        date = start
    }

    var now: Date { lock.withLock { date } }

    func advance(by seconds: Double) {
        lock.withLock { date = date.addingTimeInterval(seconds) }
    }
}
