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
/// Arming and recording are two calls because they happen in different places:
/// `armKeyWindow()` runs on the thread the key arrived on, `register` when the
/// reading it explains comes back from the border's serial queue (the value read
/// is a blocking private-API call and must never run on the caller's thread). So
/// `register(keyDriven: true)` records a reading a key asked for; it does not
/// open the window. Whether such a reading may still SPEAK for its key is the
/// owning source's call, not this gate's — a neighbour reporting the same press
/// spends the window here and marks the in-flight readings there
/// (docs/DECISIONS.md: key-origin-brightness-gate).
///
/// Known limit (rare, self-healing): a poll reading already in flight when the
/// key arrives registers before the window is armed, so it absorbs the key's
/// value silently and the HUD is missed until the next key. The tap wakes the
/// router before the event reaches the OS, and the window is now armed at key
/// time rather than when the key's own reading returns, so the sliver is one
/// reading narrower than it was; a held key re-arms and self-corrects.
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

    /// Opens the key-origin window, stamped with the key's own instant. Kept out
    /// of `register` so two orderings survive the reading arriving later, off the
    /// caller's thread: the window measures from the key rather than from
    /// whenever the read returned, and a `standDown()` that follows the key acts
    /// on a window that is already open instead of racing an arm queued behind a
    /// blocking read.
    mutating func armKeyWindow() {
        keyActivityUntil = now().addingTimeInterval(window)
    }

    /// Records a reading and returns whether it warrants a HUD. `keyDriven` is
    /// true for a reading the external `sample()` asked for (the media-key
    /// router, the suppressor's post-apply poke, the slider echo) and still
    /// speaks for it, false for the passive poll. It never arms —
    /// `armKeyWindow()` does, at key time.
    mutating func register(_ value: Double, keyDriven: Bool) -> Bool {
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
