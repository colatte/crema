import Observation

/// Observable permission state for the UI (menu warning, onboarding): polls
/// the injected permission on the injected clock, so a grant or a revocation
/// is picked up while the app runs — no relaunch required.
@MainActor
@Observable
final class AccessibilityPermissionMonitor {
    private(set) var isGranted: Bool

    @ObservationIgnored private let permission: any AccessibilityPermission
    @ObservationIgnored private let clock: any SleepClock
    @ObservationIgnored private let pollInterval: Double
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        permission: any AccessibilityPermission,
        clock: any SleepClock = ContinuousSleepClock(),
        pollInterval: Double = 2
    ) {
        self.permission = permission
        self.clock = clock
        self.pollInterval = pollInterval
        isGranted = permission.isGranted()
    }

    func start() {
        guard pollTask == nil else { return }
        // clock/interval captured by value so the sleep never retains self —
        // a strong ref parked across the await would keep the monitor alive
        // for as long as the poll it owns keeps running.
        pollTask = Task { [weak self, clock, pollInterval] in
            while !Task.isCancelled {
                try? await clock.sleep(for: pollInterval)
                self?.refresh()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refresh() {
        let granted = permission.isGranted()
        if granted != isGranted {
            isGranted = granted
        }
    }
}
