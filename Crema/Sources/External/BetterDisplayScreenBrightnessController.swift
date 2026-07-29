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
final class BetterDisplayScreenBrightnessController: ScreenBrightnessController, @unchecked Sendable {
    private let channel: any BetterDisplayCommanding
    /// The domain's key → the numeric ID BetterDisplay speaks; nil when there is
    /// no such display to address. Injected so the actuator is testable without
    /// displays attached.
    private let displayID: @Sendable (DisplayUUID?) -> Int?

    private let lock = NSLock()
    private var inFlight = false
    private var queued: Double?

    init(channel: any BetterDisplayCommanding, displayID: @escaping @Sendable (DisplayUUID?) -> Int?) {
        self.channel = channel
        self.displayID = displayID
    }

    func setBrightness(_ value: Double, on display: DisplayUUID?) async throws {
        // A display that does not resolve has been unplugged between the HUD and
        // the drag; unavailable is exactly what that is.
        guard let id = displayID(display) else { throw BrightnessCommandError.unavailable }

        // Scoped locking only: this runs in an async context, where holding a lock
        // across a suspension is exactly the shape that deadlocks.
        let drives = lock.withLock { () -> Bool in
            queued = value
            guard !inFlight else { return false }   // a running write will drain this
            inFlight = true
            return true
        }
        guard drives else { return }
        defer { lock.withLock { inFlight = false } }

        while let next = lock.withLock({ () -> Double? in
            defer { queued = nil }
            return queued
        }) {
            try await channel.setBrightness(next, displayID: id)
        }
    }

    /// The production resolver, kept next to its only caller. Nil means the
    /// built-in screen — the domain's own spelling — and anything else is a
    /// display the roster knows by UUID.
    static func liveDisplayID(_ display: DisplayUUID?) -> Int? {
        guard let display else { return ScreenTranslation.builtInDisplayID().map(Int.init) }
        return ScreenTranslation.displayID(for: display).map(Int.init)
    }
}
