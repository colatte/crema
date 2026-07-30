/// What the menu bar should say about who is receiving the media keys.
///
/// The three cases are one story told at three stages: another app is ahead and
/// Crema simply loses those keys; the app ahead is one Crema knows how to
/// cooperate with, so the line carries the fix; or the cooperation is running and
/// the line becomes a confirmation instead of a warning.
enum MediaKeyChainNotice: Equatable {
    /// Crema is first in the chain, or nothing that could take a key is ahead.
    case quiet
    /// BetterDisplay is publishing its OSD events and Crema is drawing the screen
    /// brightness HUD from them — the arrangement working, worth saying so.
    case drawingFromBetterDisplay
    /// BetterDisplay is ahead of us in the chain and has never reported: it is
    /// taking the brightness keys with its OSD integration switched off, which is
    /// the one contention the user can resolve into cooperation.
    case betterDisplayAheadAndSilent
    /// Some other app is ahead. Naming it is all Crema can honestly do — the
    /// choice of which app should own the key is the user's.
    case anotherAppAhead(String)
}

extension MediaKeyChainNotice {
    /// The coalescing window in front of the one reading in this app with a
    /// system-wide side effect: `CGGetEventTapList` resets the min/max latency
    /// counters of EVERY tap in the system, neighbouring apps' included, and the
    /// caller is a SwiftUI body rebuilt whenever SwiftUI invalidates it — which the
    /// app does not control and which is NOT the same as the user opening the menu.
    /// So a burst of rebuilds collapses into one reading
    /// (docs/DECISIONS.md: media-key-chain-contention).
    ///
    /// A WINDOW and not a set of invalidation edges, deliberately. The edges that
    /// change the answer are not enumerable from inside this process: a neighbour
    /// can install or drop a tap while already running — that is exactly what
    /// toggling its key handling does — with no notification behind it, so any edge
    /// list would keep serving a stale line for an unbounded time. And the stale
    /// line here is an ACCUSATION against a named neighbour, which is the direction
    /// the decision above says to err away from. The window bounds both sides at
    /// once: at most one reading per window, never more than one window stale, and
    /// no wiring anyone can forget.
    ///
    /// The neighbour's delivered payload is a different kind of input — a free local
    /// flag that can flip with no notification at all — so it is part of the memo
    /// KEY rather than of its age: a flip re-reads immediately.
    ///
    /// Plain stored state and NO observation, deliberately: the fill happens inside
    /// a view body, and writing observed state there is the mutation driven by
    /// rendering that the menu is careful never to do.
    @MainActor
    final class Cache {
        /// One second: longer than any burst of view rebuilds, shorter than the gap
        /// between a user changing something and looking at the menu to see it.
        static let defaultWindow = Duration.seconds(1)

        private let window: Duration
        private let now: @MainActor () -> ContinuousClock.Instant
        private var memo: (feeding: Bool, notice: MediaKeyChainNotice, readAt: ContinuousClock.Instant)?

        /// `now` is injected so a test drives the window without waiting on wall
        /// time. A timestamp read, not a timer — there is nothing to park, so it
        /// does not belong on SleepClock.
        /// Spelled `Cache.defaultWindow` rather than `Self.defaultWindow`: a default
        /// argument cannot reference the covariant `Self` of a non-final context, and
        /// the compiler rejects it outright.
        init(
            window: Duration = Cache.defaultWindow,
            now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
        ) {
            self.window = window
            self.now = now
        }

        /// `read` runs only on a miss, and receives the flag so the precedence
        /// between the two inputs stays in one place (AppCore.mediaKeyChainNotice).
        func notice(
            betterDisplayIsFeedingUs feeding: Bool,
            read: (Bool) -> MediaKeyChainNotice
        ) -> MediaKeyChainNotice {
            let instant = now()
            if let memo, memo.feeding == feeding, instant - memo.readAt < window {
                return memo.notice
            }
            let notice = read(feeding)
            memo = (feeding, notice, instant)
            return notice
        }
    }
}
