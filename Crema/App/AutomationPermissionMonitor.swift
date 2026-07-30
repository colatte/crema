import Foundation
import Observation

/// Observable Automation state for the Settings row: reads the injected
/// permission for every player the JXA fallback scripts and publishes ONE
/// aggregate the row renders.
///
/// Three properties are contract, not implementation detail.
///
/// The read is a blocking round trip to another process, so it happens off the
/// main actor and only the answer comes back — a view body must never be what
/// pays for it (`blockingCall`, Crema/Sources/BlockingCall.swift).
///
/// `refresh()` is the NON-prompting question, which is what makes it safe on a
/// timer and on a window appearing; `askForConsent()` is the prompting one and is
/// reachable only from the user's click. One ask at a time, because the prompting
/// call returns only when the user answers the dialog and a second click would
/// stack a second dialog behind the first.
///
/// The poll is started and stopped by the row that reads it, never at launch:
/// nothing else in the app needs the answer (the fallback finds out by trying),
/// and a state nobody looks at would still invalidate every view that reads it —
/// the menu deliberately does not, because its own tap-chain read is expensive
/// (docs/DECISIONS.md: automation-is-fallback-only).
@MainActor
@Observable
final class AutomationPermissionMonitor {
    /// Nil until the first answer lands. A Bool has no room for "nobody has asked
    /// yet", and the row has to be able to say exactly that instead of implying a
    /// refusal it never read.
    private(set) var state: AutomationPermissionState?

    @ObservationIgnored private let permission: any AutomationPermission
    @ObservationIgnored private let targets: [String]
    @ObservationIgnored private let clock: any SleepClock
    @ObservationIgnored private let pollInterval: Double
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    /// The per-target answers behind the aggregate: the prompt goes only to
    /// targets macOS has never decided about, so the row cannot ask about one it
    /// has no verdict for.
    @ObservationIgnored private var answers: [String: AutomationPermissionState] = [:]
    @ObservationIgnored private var isAsking = false

    init(
        permission: any AutomationPermission = AppleEventsAutomationPermission(),
        targets: [String] = JXAPlayerScript.players.map(\.bundleID),
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2
    ) {
        self.permission = permission
        self.targets = targets
        self.clock = clock
        self.pollInterval = pollInterval
    }

    /// Starts the non-prompting poll (idempotent), reading immediately so the row
    /// does not wait a full interval for its first answer. The interval matches
    /// the Accessibility monitor's, so a grant made in System Settings shows up
    /// here without reopening the window.
    func start() {
        guard pollTask == nil else { return }
        // clock/interval captured by value so the sleep never retains self — a
        // strong ref parked across the await would keep the monitor alive for as
        // long as the poll it owns keeps running.
        pollTask = Task { [weak self, clock, pollInterval] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await clock.sleep(for: pollInterval) } catch { return }
            }
        }
    }

    /// Ends the poll. Cancelling is the point, not clearing the handle: a task
    /// left holding its parked sleep wakes on the next interval and reads again
    /// with nobody watching. The last known state is kept on purpose — reopening
    /// the tab should not flash "no answer yet" over an answer that is still true,
    /// and the first pass of the next `start()` re-reads it anyway.
    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Re-reads every target without prompting. Stands down while a consent
    /// dialog is up: the only answer a read can give then is the pre-decision one,
    /// and it would land after the decision and undo it — plus each pass is a
    /// blocking round trip that would queue behind a modal nobody has answered.
    func refresh() async {
        guard !isAsking else { return }
        let permission = permission
        let targets = targets
        let read = await blockingCall {
            var answers: [String: AutomationPermissionState] = [:]
            for target in targets { answers[target] = permission.state(forBundleID: target) }
            return answers
        }
        record(read)
    }

    /// The prompting ask. It goes to the targets macOS has never decided about,
    /// in the fallback's own precedence — a target that is not running cannot be
    /// asked (there is nobody to consent about it), and a refusal is not
    /// re-askable at all, which is why the row offers the Settings pane for that
    /// state instead of this.
    func askForConsent() async {
        guard !isAsking else { return }
        let permission = permission
        let askable = targets.filter { answers[$0] == .undecided }
        guard !askable.isEmpty else { return }
        isAsking = true
        // No deadline: the call returns when the user answers, and abandoning a
        // dialog someone is still reading would report a refusal they never made.
        // The residual is one parked GCD thread, bounded to one by the guard above.
        let asked = await blockingCall {
            var answers: [String: AutomationPermissionState] = [:]
            for target in askable { answers[target] = permission.request(forBundleID: target) }
            return answers
        }
        isAsking = false
        record(asked)
    }

    private func record(_ read: [String: AutomationPermissionState]) {
        answers.merge(read) { _, new in new }
        let aggregate = AutomationPermissionState.aggregate(targets.compactMap { answers[$0] })
        if aggregate != state { state = aggregate }
    }
}
