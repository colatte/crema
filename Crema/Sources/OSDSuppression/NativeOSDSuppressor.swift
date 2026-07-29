/// Capability: replacing the native volume/brightness OSD with the app's own
/// (opt-in and reversible). Engaging must never be able to strand the user
/// without volume/brightness control — on any apply failure the affected
/// domain is *suspended* (its keys flow back to the system and the native OSD
/// gives the feedback) while the app keeps observing, and a cheap read-only
/// probe re-engages it the moment the channel recovers.
///
/// No failure path ever writes the persisted opt-in (docs/DECISIONS.md:
/// pref-sacred): the preference is the user's intent, written only by an
/// explicit toggle. A relaunch therefore
/// starts fresh — the pref is intact, so a healthy engagement is re-formed.
/// A domain that keeps failing with the channel present escalates to
/// long-suspended and surfaces in the menu; that is the only user-visible
/// signal, and it never touches the pref.
@MainActor
protocol NativeOSDSuppressor: AnyObject {
    var isEngaged: Bool { get }
    func setEngaged(_ engaged: Bool)
    /// Fired after each verified apply on a healthy domain; the owner pokes the
    /// matching brightness sampler so the app's HUD refreshes with the applied
    /// value (a key-time sample reads the pre-apply one).
    var onApplied: (@MainActor (MediaKey) -> Void)? { get set }

    /// Domains that have failed long enough (with the channel present) to be
    /// worth telling the user about — the menu names these. Transient
    /// suspensions (a device swap re-engaging in seconds) never appear here.
    var longSuspendedDomains: Set<OSDSuppressionDomain> { get }
    /// Fired when `longSuspendedDomains` changes (a domain escalates, or a
    /// long-suspended one recovers) so the owner can refresh the menu.
    var onSuspensionStateChange: (@MainActor () -> Void)? { get set }
    /// Forces an immediate recovery probe of every suspended domain — the
    /// menu's "try to reactivate now" action for an active user who fixed the
    /// cause and does not want to wait out the backoff.
    func retrySuspendedNow()
}
