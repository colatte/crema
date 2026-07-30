import Foundation
@testable import Crema

/// Test fake for the Automation (Apple Events) permission: per-target answers the
/// test controls, with the two entry points counted SEPARATELY — the whole point of
/// the split is that one of them prompts and the other must never be able to.
/// Lock-protected because the monitor asks from a GCD thread (the real call
/// blocks, so it never runs on the actor).
final class MockAutomationPermission: AutomationPermission, @unchecked Sendable {
    private let lock = NSLock()
    /// Separate from `lock`: a parked prompt must not hold the lock the recording
    /// accessors need, or a test could not observe the prompt it is waiting on.
    private let gate = NSCondition()
    private var answers: [String: AutomationPermissionState]
    private var _reads: [String] = []
    private var _prompts: [String] = []
    private var holdingPrompts = false

    init(_ answers: [String: AutomationPermissionState] = [:]) {
        self.answers = answers
    }

    /// Bundle IDs asked WITHOUT prompting, in order.
    var reads: [String] { lock.withLock { _reads } }
    /// Bundle IDs the prompting call was made for, in order.
    var prompts: [String] { lock.withLock { _prompts } }

    func set(_ state: AutomationPermissionState, for bundleID: String) {
        lock.withLock { answers[bundleID] = state }
    }

    /// Parks every prompting call, the way the real one parks until the user
    /// answers the dialog — which is what lets a second click stack a second dialog
    /// when nothing guards it.
    func holdPrompts() {
        gate.lock()
        holdingPrompts = true
        gate.unlock()
    }

    /// Releases EVERY parked prompt, not just one: a mutant that stacks a second
    /// dialog must fail the assertion, never wedge the suite on a thread nobody
    /// can free.
    func releasePrompts() {
        gate.lock()
        holdingPrompts = false
        gate.broadcast()
        gate.unlock()
    }

    func state(forBundleID bundleID: String) -> AutomationPermissionState {
        lock.withLock {
            _reads.append(bundleID)
            return answers[bundleID] ?? .unknown
        }
    }

    func request(forBundleID bundleID: String) -> AutomationPermissionState {
        lock.withLock { _prompts.append(bundleID) }
        // Wall-clock bounded, like every wait in this suite: a test that forgets to
        // release must fail loud downstream instead of hanging (TestSupport's
        // boundedWaitDeadline carries the rule).
        let deadline = Date().addingTimeInterval(5)
        gate.lock()
        while holdingPrompts, Date() < deadline {
            _ = gate.wait(until: deadline)
        }
        gate.unlock()
        return lock.withLock { answers[bundleID] ?? .unknown }
    }
}
