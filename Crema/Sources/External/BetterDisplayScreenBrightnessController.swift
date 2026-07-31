import CoreGraphics
import Foundation

/// Screen brightness written through BetterDisplay instead of through the system.
///
/// It exists because the bar and the write must speak the same scale. When a HUD
/// was drawn from BetterDisplay's report, that number is its blended level
/// (hardware plus software dimming — measured 0.625 against a hardware 0.504 on
/// the same screen), so sending the drag to the system's own actuator would move
/// the display to a level the user did not aim at. Sending it back where the
/// number came from keeps the bar honest.
///
/// Writes are coalesced latest-wins, with at most one in flight. A drag fires on
/// every frame and each write here is a round-trip to another process rather than
/// the microsecond C call the system path makes, so without this a two-second
/// drag would put dozens of requests in the air at once, resolving out of order.
/// A superseded value is simply dropped: nobody wants the level a finger passed
/// through, only the one it stopped at.
///
/// A queued level travels with the display it was meant for, because the
/// coalescing outlives the call that resolved it: one drive drains the frames that
/// arrived after it, so a bare number would land on whichever screen happened to be
/// driving — the neighbour dimming a display nobody was dragging on, in silence,
/// since the bar that asked for it is on another panel. For the same reason a call
/// reports only what reached the wire for the display IT named
/// (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
final class BetterDisplayScreenBrightnessController: ScreenBrightnessController, @unchecked Sendable {
    /// A level and the screen it belongs to, kept together for as long as the
    /// coalescing holds it — the pair is what a drain has to know to write it.
    private struct QueuedWrite {
        let value: Double
        let displayID: Int
    }

    private let channel: any BetterDisplayCommanding
    /// The domain's key → the numeric ID BetterDisplay speaks; nil when there is
    /// no such display to address. Injected so the actuator is testable without
    /// displays attached.
    private let displayID: @Sendable (DisplayUUID?) -> Int?

    private let lock = NSLock()
    private var inFlight = false
    private var queued: QueuedWrite?

    init(channel: any BetterDisplayCommanding, displayID: @escaping @Sendable (DisplayUUID?) -> Int?) {
        self.channel = channel
        self.displayID = displayID
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws -> Double {
        // A display that does not resolve has been unplugged between the HUD and
        // the drag; unavailable is exactly what that is.
        guard let id = displayID(display) else { throw BrightnessCommandError.unavailable }

        // Scoped locking only: this runs in an async context, where holding a lock
        // across a suspension is exactly the shape that deadlocks.
        let drives = lock.withLock { () -> Bool in
            queued = QueuedWrite(value: value, displayID: id)
            guard !inFlight else { return false }   // a running write will drain this
            inFlight = true
            return true
        }
        // Coalesced: nothing was written here, but the driver will write this very
        // value to this very display, and returning it now keeps the echo level with
        // the finger.
        guard drives else { return value }
        defer { lock.withLock { inFlight = false } }

        // What this call may echo: the newest level the drain put on the wire for
        // the display this call named. The frames it drains carry their own screens,
        // so the last one out can belong to another bar.
        var written: Double?
        while let next = lock.withLock({ () -> QueuedWrite? in
            defer { queued = nil }
            return queued
        }) {
            try await channel.setBrightness(next.value, displayID: next.displayID)
            if next.displayID == id { written = next.value }
        }
        // Never the argument: a call that drives stays inside the drain loop writing
        // everything that arrived after it, so by the time it returns, the value it
        // was CALLED with is several frames behind the finger. Echoing that argument
        // is what made a fast drag flick backwards before the next frame pulled it
        // forward again — observed on hardware, on the bar drawn on the external
        // monitor itself. Falling back to the argument covers the one case where the
        // drain wrote nothing for this display: a newer frame replaced this level
        // before the drain reached it, which is coalescing doing its job.
        return written ?? value
    }

    /// The production resolver, kept next to its only caller. Nil means the
    /// built-in screen — the domain's own spelling — and anything else is a
    /// display the roster knows by UUID.
    static func liveDisplayID(_ display: DisplayUUID?) -> Int? {
        guard let display else { return ScreenTranslation.builtInDisplayID().map(Int.init) }
        return ScreenTranslation.displayID(for: display).map(Int.init)
    }
}
