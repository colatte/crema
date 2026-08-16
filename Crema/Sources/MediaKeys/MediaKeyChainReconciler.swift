import Foundation

/// Where Crema sits in the media-key delivery chain.
enum MediaKeyChain: Equatable {
    /// Nothing that could swallow our keys sits in front of us.
    case ours
    /// Another process's filter tap precedes ours and asked for the same events.
    /// It can take a key press and we would never learn it happened: no observed
    /// key, no HUD of ours, and the native OSD in its place — indistinguishable,
    /// from inside, from a tap that stopped delivering.
    case precededBy(pid_t)
    /// We have no tap in the registry (permission missing, install pending), or
    /// the registry could not be read. Nothing to say about a chain we are not in.
    case unknown
}

/// Pure decision over a registry snapshot: is anything positioned to take our
/// keys before we see them?
///
/// This exists because two apps can legitimately want the same key — a display
/// utility driving brightness with its own curve and Crema drawing the HUD —
/// and the winner is decided by whoever inserted last at login, which no user
/// can diagnose from the outside. Crema does not fight for the position (see
/// docs/DECISIONS.md: media-key-chain-contention); it names who won.
enum MediaKeyChainReconciler {
    static func chain(ourPID: pid_t, mask: UInt64, in entries: [EventTapEntry]) -> MediaKeyChain {
        guard let ours = entries.firstIndex(where: { $0.pid == ourPID }) else { return .unknown }
        let weAreAtHIDLocation = entries[ours].precedesSessionTaps
        let contender = entries.enumerated().first { index, entry in
            guard entry.pid != ourPID,
                  entry.isEnabled,
                  entry.canConsume,
                  entry.mask & mask != 0,
                  // Two documented reasons a tap cannot be ahead of us, both of
                  // which the registry used to discard. The annotated-session
                  // point is DOWNSTREAM of the session point in the pipeline
                  // (`CGEventTypes.h` orders the three), and a per-process tap
                  // only sees its target's events. Either way the neighbour is
                  // innocent, and naming it is the false accusation this whole
                  // decision errs away from.
                  !entry.followsSessionTaps,
                  entry.processBeingTapped == nil
            else { return false }
            // Different locations: the HID one is fed first, wherever it is
            // listed. Same location: the list order is the delivery order.
            // Stated symmetrically so it stays true whichever location we tap.
            if entry.precedesSessionTaps != weAreAtHIDLocation {
                return entry.precedesSessionTaps
            }
            return index < ours
        }
        guard let contender else { return .ours }
        return .precededBy(contender.element.pid)
    }
}
