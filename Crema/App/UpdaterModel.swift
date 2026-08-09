import Combine
import SwiftUI
#if !DEBUG
import Sparkle
#endif

/// App-shell wrapper over Sparkle's updater. Auto-update is an app-lifecycle
/// concern, so it lives in the App layer — never in the Coordinator or Sources
/// (which stay ignorant of distribution).
///
/// The Sparkle controller is constructed only in Release: dev builds must never
/// contact the appcast feed, so in Debug this type is an inert shell (no
/// controller, `canCheckForUpdates` and `hasPendingUpdate` stay false) and the
/// "Check for Updates…" menu item does not exist at all (see `CremaApp`). The empty
/// shell keeps the type instantiable in Debug/test builds so its build-config
/// contract can be pinned by a test without ever touching Sparkle.
///
/// `NSObject` because Sparkle's user-driver delegate protocol inherits
/// `NSObjectProtocol`; the conformance itself is Release-only, below.
@MainActor
final class UpdaterModel: NSObject, ObservableObject {
    /// Whether this build ships the updater (menu item + Sparkle controller).
    /// True only in Release; the build-configuration contract
    /// `SparkleUpdaterTests` pins (the menu gates itself on `#if !DEBUG` and
    /// `canCheckForUpdates`, never on this flag).
    static var isSupported: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Mirrors Sparkle's `canCheckForUpdates` so the menu item disables while a
    /// check is already in flight (the published-property pattern). Always false
    /// in Debug, where no controller exists.
    @Published private(set) var canCheckForUpdates = false

    /// A scheduled check found an update the user has not yet acted on. A read
    /// mirror for the menu — the truth lives in Sparkle's own session, and this
    /// only says whether the menu should point at it.
    ///
    /// It exists because Crema is an accessory app: Sparkle shows a scheduled
    /// update alert BEHIND every other running app when the app is not frontmost
    /// (its own log warns background apps about exactly this), and an app with no
    /// Dock tile gives the user nothing to bring it forward with. The menu bar is
    /// the only surface the user comes back to.
    @Published private(set) var hasPendingUpdate = false

    #if !DEBUG
    /// A `var`, and the only reason is two-phase init: the controller takes THIS
    /// object as its user-driver delegate, and `self` does not exist until after
    /// `super.init()`, which a stored constant would have to precede. Sparkle keeps
    /// the delegate weakly, so the model outliving the controller is the contract,
    /// not an accident.
    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        // Idiomatic modern setup: start the updater immediately, no updater
        // delegate. Consent stays Sparkle's own — we set no
        // SUEnableAutomaticChecks/SUAutomaticallyUpdate defaults, so Sparkle
        // asks on the second launch and installs only on a user click.
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: self
        )
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents Sparkle's update UI. The caller activates the app first (accessory
    /// apps have no key window, so the panel would otherwise open behind). Also the
    /// way an already-presented scheduled alert is brought back into focus, which is
    /// what the menu's pending-update button needs.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    /// Guarded write: this object is a `@StateObject` of the App's scene, so every
    /// change republishes the whole menu — including the status block that reads the
    /// tap chain. Writing only on a real change keeps a pending update to one
    /// rebuild instead of one per delegate callback.
    private func setPendingUpdate(_ pending: Bool) {
        guard hasPendingUpdate != pending else { return }
        hasPendingUpdate = pending
    }
    #else
    override init() { super.init() }

    func checkForUpdates() {}
    #endif
}

#if !DEBUG
/// Gentle scheduled update reminders (sparkle-project.org/documentation/gentle-reminders).
/// Sparkle keeps showing its own alert — we do not take over presentation — and this
/// only adds the signpost an accessory app needs: a background app's scheduled alert
/// opens behind everything, so without a line in the menu the user is told about the
/// update by a window they never see. Declaring support also silences Sparkle's
/// (correct) log warning that a background app schedules checks with no gentle path.
///
/// Every callback hops to the main actor with a Task rather than
/// `MainActor.assumeIsolated`, which the neighbouring system callbacks use: this
/// house only assumes isolation it can back with a re-runnable measurement, and this
/// path exists solely in Release, where the Debug-hosted suite cannot measure it
/// (docs/DECISIONS.md: assumed-isolation-is-measured). The cost of hopping is
/// ordering, and a mirror that flips at most twice per update session can pay it —
/// the ordering-sensitive sites are the ones that assume.
extension UpdaterModel: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        // A check the user asked for already puts the alert in front of them, so a
        // menu line pointing at it would only name what they are looking at.
        guard !state.userInitiated else { return }
        Task { @MainActor in self.setPendingUpdate(true) }
    }

    /// The user reached the alert (brought it into focus, or chose install/skip), so
    /// the menu has nothing left to point at.
    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.setPendingUpdate(false) }
    }

    /// The session ended — dismissed, skipped, or failed. Clearing here too is what
    /// keeps the line from outliving the update it announces.
    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.setPendingUpdate(false) }
    }
}
#endif
