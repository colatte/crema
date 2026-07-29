/// Reconciles what the user ASKED for against what macOS currently reports —
/// the pure decision behind the menu's launch-at-login warning.
///
/// The registration lives beyond the Background Task Management boundary, and
/// macOS invalidates it whenever the bundle's code identity changes (a rebuild,
/// a reinstall, and — the one that will hit every installed user at once — the
/// eventual move to Developer ID). The app can't see that happen: the status
/// simply reads `.notRegistered` afterwards, and without a persisted intent the
/// user's choice disappears in silence, which is exactly what was diagnosed on
/// hardware (docs/DECISIONS.md: login-item-intent, the J7 class).
///
/// The intent alone is not enough to warn honestly, because "gone" has two very
/// different authors: macOS revoking it (the user should hear about it) and the
/// user removing it in System Settings (the app must shut up and respect that).
/// The recorded BUILD tells them apart — a registration that vanished across a
/// build change was revoked; one that vanished under the same build was removed
/// by the user. Same epoch idiom as the scrub's seek guard: an actor's action is
/// only honored while its generation is still current.
enum LoginItemReconciler {
    enum Outcome: Equatable {
        /// Nothing to say: either the user never asked, or reality matches.
        case quiet
        /// Registered but parked by macOS awaiting approval.
        case needsApproval
        /// The user asked for it, the record is gone, and the bundle changed
        /// since — warn, and offer to turn it back on with one click.
        case revokedByUpdate
        /// Gone under the same build: the user removed it outside the app.
        /// Forget the intent instead of nagging.
        case userRemoved
    }

    /// `recordedBuild` is the CFBundleVersion captured when the user last turned
    /// the toggle on; nil means the intent predates that bookkeeping (only
    /// reachable by hand-editing defaults), which is treated as a revocation —
    /// warning once is recoverable, silently dropping the user's choice is not.
    static func outcome(
        intends: Bool,
        recordedBuild: String?,
        currentBuild: String,
        status: LoginItemStatus
    ) -> Outcome {
        guard intends else { return .quiet }
        switch status {
        case .enabled:
            return .quiet
        case .requiresApproval:
            return .needsApproval
        case .notRegistered:
            return recordedBuild == currentBuild ? .userRemoved : .revokedByUpdate
        }
    }
}
