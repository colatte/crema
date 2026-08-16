import CoreGraphics
import Foundation

/// What a brightness call put on screen versus on the wire. The bar needs an
/// echo the instant the frame arrives (a fill frozen under a moving finger reads
/// as a broken control), but only a level that actually reached the wire may
/// serve as EVIDENCE — the level a failed gesture rolls back to. Folding the two
/// into one bare Double is how an echoed-but-never-written level once became
/// "confirmed" and the rollback settled the bar on a brightness no display went
/// to (docs/DECISIONS.md: the-bar-never-outruns-the-screen).
enum BrightnessWriteEcho: Equatable, Sendable {
    /// This level went out on the wire for the display the call named.
    case written(Double)
    /// Echo only: the level is queued behind (or was superseded by) another
    /// frame. The driving call will write it, or surface it inside its error —
    /// nothing about it is confirmed yet.
    case coalesced(Double)
}

/// The coalescing writer's failure, carrying the frame its own coalesced echo
/// already promised. When the drain's write fails, no driver is left for the
/// newest level — a frame still queued behind the failed write, or, with the
/// queue empty, the failed frame itself, which can be newer than the driving
/// call's argument because the drain writes frames that queued after it. That
/// frame leaves WITH the error, and the caller's fallback writes it instead of
/// the argument the drain was called with, which by then is frames behind the
/// finger.
struct BrightnessWriteFailure: Error {
    struct Orphan: Equatable, Sendable {
        let value: Double
        let display: DisplayUUID?
    }

    let underlying: any Error
    /// The newest level nobody will write, extracted under the same lock that
    /// released the drain: the frame still queued behind the failed write when
    /// one exists, otherwise the frame the failed write was carrying. This
    /// writer always fills it; nil is left for a thrower with no frame to name.
    let orphan: Orphan?
}

/// A screen-brightness actuator whose echo can precede its write. The plain
/// `ScreenBrightnessController` return value cannot say which of the two it is,
/// and the Coordinator must not treat an echo as a confirmed write — so a
/// conformer here offers the distinction, and its failures are
/// `BrightnessWriteFailure`, carrying the frame nobody else will write.
protocol CoalescingScreenBrightnessWriting: ScreenBrightnessController {
    func applyBrightness(_ value: Double, on display: DisplayUUID?) async throws -> BrightnessWriteEcho
}

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
final class BetterDisplayScreenBrightnessController: CoalescingScreenBrightnessWriting, @unchecked Sendable {
    /// A level and the screen it belongs to, kept together for as long as the
    /// coalescing holds it — the pair is what a drain has to know to write it,
    /// and what an orphan has to know to leave with the error.
    private struct QueuedWrite {
        let value: Double
        let display: DisplayUUID?
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
        switch try await applyBrightness(value, on: display) {
        case .written(let level), .coalesced(let level): return level
        }
    }

    func applyBrightness(_ value: Double, on display: DisplayUUID?) async throws -> BrightnessWriteEcho {
        // A display that does not resolve has been unplugged between the HUD and
        // the drag; unavailable is exactly what that is.
        guard let id = displayID(display) else { throw BrightnessCommandError.unavailable }

        // Scoped locking only: this runs in an async context, where holding a lock
        // across a suspension is exactly the shape that deadlocks.
        let drives = lock.withLock { () -> Bool in
            queued = QueuedWrite(value: value, display: display, displayID: id)
            guard !inFlight else { return false }   // a running write will drain this
            inFlight = true
            return true
        }
        // Coalesced: nothing was written here. The driver will write this very
        // value to this very display (or surface it inside its error), and echoing
        // it now keeps the bar level with the finger — but the echo is marked for
        // what it is, so nobody upstream mistakes it for a confirmed write.
        guard drives else { return .coalesced(value) }

        // What this call may confirm: the newest level the drain put on the wire
        // for the display this call named. The frames it drains carry their own
        // screens, so the last one out can belong to another bar.
        var written: Double?
        while true {
            // The decision to stop draining and the release of inFlight happen in
            // ONE critical section. Split apart (queued check here, inFlight reset
            // in a defer), a frame slipping in between saw inFlight still true,
            // echoed as coalesced, and was never drained by anyone — the screen
            // stayed a level behind a bar that reported success.
            let next = lock.withLock { () -> QueuedWrite? in
                guard let pending = queued else {
                    inFlight = false
                    return nil
                }
                queued = nil
                return pending
            }
            guard let next else { break }
            do {
                try await channel.setBrightness(next.value, displayID: next.displayID)
            } catch {
                // The drain stops here, and any frame queued behind the failed
                // write has no driver left: it leaves WITH the error, taken under
                // the same lock that releases the drain, so the caller's fallback
                // can honour the level its coalesced echo already promised. With
                // the queue empty the failed frame itself leaves instead — being
                // drained, it can be newer than the driving call's argument, and
                // an error carrying nothing would point the fallback at that
                // argument: a level the finger only passed through.
                let orphan = lock.withLock { () -> BrightnessWriteFailure.Orphan? in
                    defer {
                        queued = nil
                        inFlight = false
                    }
                    return queued.map { .init(value: $0.value, display: $0.display) }
                }
                throw BrightnessWriteFailure(
                    underlying: error,
                    orphan: orphan ?? .init(value: next.value, display: next.display)
                )
            }
            if next.displayID == id { written = next.value }
        }
        // Never the argument: a call that drives stays inside the drain loop writing
        // everything that arrived after it, so by the time it returns, the value it
        // was CALLED with is several frames behind the finger. Echoing that argument
        // is what made a fast drag flick backwards before the next frame pulled it
        // forward again — observed on hardware, on the bar drawn on the external
        // monitor itself. When the drain wrote nothing for this display — a newer
        // frame replaced this level before the drain reached it, coalescing doing
        // its job — the argument comes back marked coalesced, never as evidence.
        if let written { return .written(written) }
        return .coalesced(value)
    }

    /// The production resolver, kept next to its only caller. Nil means the
    /// built-in screen — the domain's own spelling — and anything else is a
    /// display the roster knows by UUID.
    static func liveDisplayID(_ display: DisplayUUID?) -> Int? {
        guard let display else { return ScreenTranslation.builtInDisplayID().map(Int.init) }
        return ScreenTranslation.displayID(for: display).map(Int.init)
    }
}
