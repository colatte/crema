import AppKit
import CoreGraphics

/// One installed event tap, translated at the border.
///
/// The system's tap registry is the only view of the delivery chain that comes
/// from OUTSIDE our process: `CFMachPortIsValid` and `CGEvent.tapIsEnabled`
/// describe our own port and nothing else, so neither can ever reveal that
/// someone in front of us is taking our keys.
struct EventTapEntry: Equatable, Sendable {
    let pid: pid_t
    let isEnabled: Bool
    /// A filter tap can swallow an event before it reaches us; a listen-only
    /// tap never can, wherever it sits in the chain.
    let canConsume: Bool
    /// The events this tap asked for. Overlap with our mask is what makes it a
    /// contender for the same keys.
    let mask: UInt64
    /// A tap at the HID location is fed before every session tap regardless of
    /// insertion order — the one piece of chain order the SDK actually promises
    /// (CGEventTapLocation: HID events enter the window server, and only then a
    /// login session).
    let precedesSessionTaps: Bool

    /// True when this tap sits DOWNSTREAM of a session tap, so it can never take
    /// an event before we do.
    ///
    /// `CGEventTapLocation` is an ordered pipeline — `kCGHIDEventTap = 0`,
    /// `kCGSessionEventTap`, `kCGAnnotatedSessionEventTap` (`CGEventTypes.h`) —
    /// and only the first two were modelled. Everything that was not HID landed
    /// in one bucket where registry index order decided, so a neighbour tapping
    /// at the annotated-session point could be NAMED as the app eating your
    /// media keys purely for being listed earlier. The decision this feeds errs
    /// toward silence for exactly that reason: a missing line costs a
    /// diagnostic, a false line accuses a neighbour who is innocent by the
    /// documented pipeline.
    let followsSessionTaps: Bool

    /// The pid this tap is scoped to, or nil for a session-wide one —
    /// `processBeingTapped`, documented in the header as "Zero if not a
    /// per-process tap".
    ///
    /// Dropping it made a per-PID tap indistinguishable from a session-wide one,
    /// and apps routinely tap their OWN process. Such a tap sees only its
    /// target's events, so it cannot be ahead of us for the media keys no
    /// matter what its mask says.
    let processBeingTapped: pid_t?
}

/// Reads the system's event-tap registry, behind a protocol so the chain
/// decision is unit-testable without installing real taps.
protocol EventTapRegistry: Sendable {
    /// Every installed tap, in the order the system lists them: insertion order,
    /// newest first (matching `.headInsertEventTap`), which is also delivery
    /// order. Verified on hardware in both directions — the app ahead of us ate
    /// the brightness keys, the app behind us did not — but NOT documented by
    /// the SDK, which is why everything built on it degrades to silence rather
    /// than to action (docs/DECISIONS.md: media-key-chain-contention).
    func entries() -> [EventTapEntry]

    /// Display name of the app owning `pid`, when it has one.
    func appName(forPID pid: pid_t) -> String?

    /// Bundle identifier of the app owning `pid`. Identity checks use this and
    /// never the display name, which is localized and user-renamable.
    func bundleID(forPID pid: pid_t) -> String?
}

/// The real CoreGraphics-backed registry.
struct LiveEventTapRegistry: EventTapRegistry {
    /// Read only at user-initiated moments, never on a poll: the header states
    /// that each call resets the min/max latencies of ALL registered taps to
    /// their averages, so a monitoring tool watching the same registry would
    /// lose its best/worst-case readings to our polling.
    func entries() -> [EventTapEntry] {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return [] }
        var taps = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &taps, &count) == .success else { return [] }
        return taps.prefix(Int(count)).map { tap in
            EventTapEntry(
                pid: tap.tappingProcess,
                isEnabled: tap.enabled,
                canConsume: tap.options == .defaultTap,
                mask: tap.eventsOfInterest,
                precedesSessionTaps: tap.tapPoint == .cghidEventTap,
                followsSessionTaps: tap.tapPoint == .cgAnnotatedSessionEventTap,
                processBeingTapped: tap.processBeingTapped == 0 ? nil : tap.processBeingTapped
            )
        }
    }

    /// Agents and daemons have no localized name; the caller stays silent rather
    /// than naming a bare pid at the user.
    func appName(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    func bundleID(forPID pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
