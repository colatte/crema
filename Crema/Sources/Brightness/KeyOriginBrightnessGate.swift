import Foundation

/// The key-origin gate shared by both brightness HUD sources (screen and
/// keyboard). Their value reads look identical whether a key or the ambient
/// light sensor moved the level (screen auto-brightness, keyboard backlight
/// auto-adjust); only the origin differs, and a key `sample()` is the origin
/// signal. So a key arms a short window and a poll emits only inside it — a
/// change with no recent key is the sensor and stays silent. An emit consumes
/// the window, so one key press is one HUD and a sensor change in its tail is
/// silent. The launch value baselines without emitting.
///
/// Known limit (rare, self-healing): the owning source's poll and a key
/// `register` race under the source's lock, so a poll landing in the sliver
/// between the OS applying a key's value and the router's `sample()` absorbs
/// that value silently and the HUD is missed until the next key. The tap wakes
/// the router before the event reaches the OS, so it takes a delayed router
/// task on a single tap to hit; a held key re-arms and self-corrects.
///
/// Not thread-safe: the owning source mutates it under its own lock.
struct KeyOriginBrightnessGate {
    private let window: Double
    private let now: () -> Date
    private var lastValue: Double?
    private var keyActivityUntil: Date?

    init(window: Double, now: @escaping () -> Date, baseline: Double?) {
        self.window = window
        self.now = now
        self.lastValue = baseline
    }

    /// Records a reading and returns whether it warrants a HUD. `keyDriven` is
    /// true for the external `sample()` (the media-key router or the
    /// suppressor's post-apply poke), false for the passive poll.
    mutating func register(_ value: Double, keyDriven: Bool) -> Bool {
        if keyDriven { keyActivityUntil = now().addingTimeInterval(window) }
        let previous = lastValue
        lastValue = value
        let armed = keyActivityUntil.map { now() < $0 } ?? false
        let emit = (previous.map { $0 != value } ?? false) && (keyDriven || armed)
        if emit { keyActivityUntil = nil }
        return emit
    }
}
