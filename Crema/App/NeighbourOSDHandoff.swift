import Observation
import os

/// Takes a neighbour app's own indicator over while Crema replaces the system
/// indicators, and hands it back when Crema stops. The arrangement is the one
/// BetterDisplay's Guide prescribes for a receiving app ("Third-party app
/// integration", "Coordinate feedback settings through requests", read
/// 2026-10-18): save the switches, turn dispatch on and the replaced overlay off,
/// and on shutdown restore what was saved without blindly turning anything on or
/// off (docs/DECISIONS.md: the-neighbour-indicator-is-borrowed).
///
/// Three rules carry it.
/// - Only what Crema changed is handed back, and only while it still reads as
///   Crema left it: a switch the user flipped in the neighbour's window since is
///   theirs, and is forgotten rather than overwritten.
/// - The original is recorded BEFORE the write leaves, because the neighbour
///   persists the write: a Crema that dies between the two still knows what it
///   owes, and its next launch pays it.
/// - Silence ends the pass and keeps what is owed. The next edge (either app
///   launching, a lock change, the switch) tries again; nothing polls.
///
/// One pass at a time, latest intent wins: a pass reads the intent when it
/// starts, and a change during it owes one more pass after it.
@MainActor
@Observable
final class NeighbourOSDHandoff {
    enum Status: Equatable {
        /// Not wanted with nothing owed, or the neighbour is not running.
        case idle
        /// The take-over read back as needed: the neighbour dispatches and its own
        /// indicator is off.
        case inPlace
        /// The neighbour did not answer; what is owed stays owed.
        case unanswered
        /// The neighbour said no, or a switch did not read back as written.
        case refused
    }

    /// Most passes end where they began (a lock edge, a redundant decision), and
    /// the menu's status block reads this, whose rebuild can pay a tap-chain read.
    /// No guard is written for it: `@Observable` expands an equality check into the
    /// setter (`shouldNotifyObservers`, `lhs != rhs` for an `Equatable` value), so an
    /// unchanged write notifies nobody as long as `Status` stays `Equatable`.
    private(set) var status: Status = .idle {
        didSet { if status != oldValue { logger.info("neighbour OSD handoff: \(String(describing: self.status), privacy: .public)") } }
    }

    @ObservationIgnored private let channel: any OSDSettingsChannel
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let isNeighbourRunning: @MainActor () -> Bool
    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var quitting = false
    @ObservationIgnored private var passOwed = false
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger.crema("External")

    init(
        channel: any OSDSettingsChannel,
        preferences: Preferences,
        isNeighbourRunning: @escaping @MainActor () -> Bool
    ) {
        self.channel = channel
        self.preferences = preferences
        self.isNeighbourRunning = isNeighbourRunning
    }

    /// Whether Crema replaces the indicators right now: opted in and the screen
    /// unlocked, the decision the suppressor follows (SuppressionLockController).
    /// Ignored once quitting has begun, so a late edge cannot take back what the
    /// quit is handing back.
    func setWanted(_ wanted: Bool) {
        guard !quitting else { return }
        self.wanted = wanted
        reconcile()
    }

    /// A pass against the current intent: the neighbour may have just launched, or
    /// a session that ended without handing back may have left something owed.
    func reconcile() {
        passOwed = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            while let self, self.passOwed {
                self.passOwed = false
                await self.runPass()
            }
            self?.worker = nil
        }
    }

    /// The neighbour's process ended: a verdict about it, a refusal or its silence,
    /// stops being advice the person can act on. What is owed stays owed, for its
    /// next launch.
    func neighbourTerminated() {
        status = .idle
    }

    /// Hands everything back before the process ends, whatever the intent: the
    /// neighbour keeps what it was told past Crema's exit. Returns when the pass is
    /// done, or when the neighbour's silence ended it.
    func handBackBeforeQuitting() async {
        quitting = true
        wanted = false
        reconcile()
        while let worker { await worker.value }
    }

    private func runPass() async {
        let wanted = self.wanted
        let owes = NeighbourOSDSetting.allCases.contains { preferences.neighbourOSDOriginal($0) != nil }
        guard wanted || owes, isNeighbourRunning() else {
            status = .idle
            return
        }
        do throws(OSDSettingsError) {
            if wanted {
                try await takeOver()
                status = .inPlace
            } else {
                try await handBack()
                status = .idle
            }
        } catch where !isNeighbourRunning() {
            // A neighbour that quit mid-pass is gone, not unresponsive: its
            // termination may already have been heard while the deadline ran.
            status = .idle
        } catch {
            status = error == .unanswered ? .unanswered : .refused
        }
    }

    private func takeOver() async throws(OSDSettingsError) {
        for setting in NeighbourOSDSetting.allCases {
            let current = try await channel.read(setting)
            guard current != setting.heldValue else { continue }
            preferences.setNeighbourOSDOriginal(current, for: setting)
            try await channel.write(setting, to: setting.heldValue)
            guard try await channel.read(setting) == setting.heldValue else { throw .refused }
            logger.info("took over the neighbour's \(setting.rawValue, privacy: .public)")
        }
    }

    private func handBack() async throws(OSDSettingsError) {
        for setting in NeighbourOSDSetting.allCases.reversed() {
            guard let original = preferences.neighbourOSDOriginal(setting) else { continue }
            // Anything other than the value Crema wrote is the user's own choice
            // since, and stands.
            if try await channel.read(setting) == setting.heldValue {
                try await channel.write(setting, to: original)
                guard try await channel.read(setting) == original else { throw .refused }
                logger.info("handed back the neighbour's \(setting.rawValue, privacy: .public)")
            }
            preferences.setNeighbourOSDOriginal(nil, for: setting)
        }
    }
}
