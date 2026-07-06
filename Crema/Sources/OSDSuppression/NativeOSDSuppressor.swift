/// Capability: replacing the native volume/brightness OSD with the app's own
/// (opt-in and reversible). Engaging must never be able to strand the
/// user without volume/brightness control — implementations degrade back to
/// the native behavior on any failure and report it through
/// `onAutoDisengage`.
@MainActor
protocol NativeOSDSuppressor: AnyObject {
    var isEngaged: Bool { get }
    func setEngaged(_ engaged: Bool)
    /// Fired when a failed apply forces the suppressor off (the degradation
    /// path); the owner flips the persisted preference so the menu/Settings
    /// state reflects reality.
    var onAutoDisengage: (@MainActor () -> Void)? { get set }
    /// Fired after each verified apply; the owner pokes the matching
    /// brightness sampler so the app's HUD refreshes with the applied value
    /// (a key-time sample reads the pre-apply one).
    var onApplied: (@MainActor (MediaKey) -> Void)? { get set }
}
