/// A media-key source whose owned keys can be consumed — swallowed before the
/// system processes them. The seam the OSD suppressor engages; setting nil
/// restores pure observation, which is the suppression's reversibility story.
///
/// The consumer is called on *both* phases of an owned key (key-down, its
/// autorepeats, and key-up) and returns whether that specific event must be
/// swallowed. The decision has to be synchronous, per key, and consistent
/// across the two phases: swallowing a down while leaking its up (or the
/// reverse) leaves an orphaned half-press in the system's key pairing. With
/// per-domain suspension (A1) the suppressor passes a suspended domain's keys
/// straight through, so this per-event Bool is what lets one domain fall back
/// to the native OSD while the others stay suppressed.
protocol MediaKeyConsuming: AnyObject, Sendable {
    /// `isDown` is true for a key-down or autorepeat, false for a key-up.
    /// The return value is whether to swallow the event.
    typealias Consumer = @Sendable (MediaKey, _ fine: Bool, _ isDown: Bool) -> Bool
    func setConsumer(_ consumer: Consumer?)
}
