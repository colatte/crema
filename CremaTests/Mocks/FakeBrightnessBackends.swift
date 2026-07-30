import Foundation
@testable import Crema

/// Test fake for the brightness backend (one shape serves screen and keyboard,
/// like the protocol): the test drives value and availability; records writes.
/// Lets the source/controller logic run without the real API.
/// `writeSucceeds` decouples the write result from availability so the
/// apply-and-verify failure path (available, but the write does not take) is
/// reachable; nil keeps the natural "succeeds while available" behavior.
final class FakeBrightnessBackend: BrightnessBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Float?
    private var _available: Bool
    private var _writeSucceeds: Bool?
    private var _writes: [Float] = []
    private var _readsStarted = 0
    private var _readCount = 0
    private var _mainThreadReads = 0
    private var _readGate: DispatchSemaphore?

    init(available: Bool = true, value: Float? = 0.5, writeSucceeds: Bool? = nil) {
        _available = available
        _value = value
        _writeSucceeds = writeSucceeds
    }

    var isAvailable: Bool { lock.withLock { _available } }
    var value: Float? {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }

    var writes: [Float] { lock.withLock { _writes } }

    /// Two reading counters, because they answer different questions.
    /// `readsStarted` counts readings that have BEGUN — bumped before `readGate`
    /// can park one, which is the only way to observe a reading deliberately stuck
    /// in flight; `readCount` counts readings that have RETURNED, which is the
    /// barrier a test needs before moving `value` again. `mainThreadReads` is WHERE
    /// they ran: the source reads on its own serial queue precisely so a blocking
    /// private-API call never lands on the caller's thread.
    var readsStarted: Int { lock.withLock { _readsStarted } }
    var readCount: Int { lock.withLock { _readCount } }
    var mainThreadReads: Int { lock.withLock { _mainThreadReads } }

    /// Parks every reading until the test signals it — the only way to hold one in
    /// flight. DispatchSemaphore, like BlockingCallTests: a waiter that needed the
    /// read to finish could not see the state being asserted about it.
    var readGate: DispatchSemaphore? {
        get { lock.withLock { _readGate } }
        set { lock.withLock { _readGate = newValue } }
    }

    /// Suspend until a reading past `mark` has begun, or has returned, bounded by
    /// the suite's wall clock (TestSupport: boundedWaitDeadline) so a reading that
    /// never comes fails loudly instead of wedging the run. The verdict comes back
    /// so call sites can `#expect` it.
    func awaitReadStarted(after mark: Int) async -> Bool {
        await eventuallyOffActor { self.readsStarted > mark }
    }

    func awaitRead(after mark: Int) async -> Bool {
        await eventuallyOffActor { self.readCount > mark }
    }

    func read() -> Float? {
        lock.lock()
        _readsStarted += 1
        if Thread.isMainThread { _mainThreadReads += 1 }
        let gate = _readGate
        lock.unlock()
        gate?.wait()
        return lock.withLock {
            _readCount += 1
            return _value
        }
    }

    func write(_ value: Float) -> Bool {
        lock.withLock {
            _writes.append(value)
            _value = value
            return _writeSucceeds ?? _available
        }
    }
}
