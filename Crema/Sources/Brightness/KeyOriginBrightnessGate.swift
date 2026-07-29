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
/// Contract: a consumed media key always produces feedback. At a scale
/// boundary the clamped write is a no-op (the read comes back unchanged), yet
/// native still flashes the full/empty bar — so a key-driven read pinned at 0
/// or 1 emits a refresh HUD showing the clamped value even when the value did
/// not move. A pure poll never triggers this: the ambient-sensor gate stays
/// intact (only a real change, armed, emits for the sensor). This is the
/// keyDriven-vs-poll seam, not keyDriven-vs-armed.
///
/// Not thread-safe: the owning source mutates it under its own lock.
struct KeyOriginBrightnessGate {
    /// The normalized scale ends: a key clamped here applies as a no-op, so the
    /// read is unchanged yet still owes the native full/empty-bar feedback.
    private static let minValue: Double = 0
    private static let maxValue: Double = 1

    private let window: Double
    private let now: () -> Date
    private var lastValue: Double?
    private var keyActivityUntil: Date?

    init(window: Double, now: @escaping () -> Date, baseline: Double?) {
        self.window = window
        self.now = now
        self.lastValue = baseline
    }

    /// Spends the window a key opened, without recording a value: someone else
    /// reported this change and is drawing it, so a later poll must stay silent
    /// instead of adding a second, differently-measured reading. The value is
    /// deliberately not taken — the other authority's scale is its own — and the
    /// next poll re-baselines on its own.
    mutating func standDown() {
        keyActivityUntil = nil
    }

    /// Records a reading and returns whether it warrants a HUD. `keyDriven` is
    /// true for the external `sample()` (the media-key router or the
    /// suppressor's post-apply poke), false for the passive poll.
    mutating func register(_ value: Double, keyDriven: Bool) -> Bool {
        if keyDriven { keyActivityUntil = now().addingTimeInterval(window) }
        let previous = lastValue
        lastValue = value
        let armed = keyActivityUntil.map { now() < $0 } ?? false
        let changed = previous.map { $0 != value } ?? false
        // A key-driven no-op at a scale boundary (0 or 1) still refreshes the
        // HUD; a poll or a mid-scale no-op does not (the step always moves the
        // value mid-scale, so an unchanged mid read is a redundant poke).
        let atBoundary = value == Self.minValue || value == Self.maxValue
        let boundaryRefresh = keyDriven && !changed && previous != nil && atBoundary
        let emit = (changed && (keyDriven || armed)) || boundaryRefresh
        if emit { keyActivityUntil = nil }
        return emit
    }
}
