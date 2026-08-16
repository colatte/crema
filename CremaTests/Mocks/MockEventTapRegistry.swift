import Foundation
@testable import Crema

/// A scripted view of the system's tap registry: the tests describe a chain and
/// the reconciler reads it exactly as it would read the real one.
struct MockEventTapRegistry: EventTapRegistry {
    var taps: [EventTapEntry] = []
    var names: [pid_t: String] = [:]
    var bundleIDs: [pid_t: String] = [:]

    func entries() -> [EventTapEntry] { taps }
    func appName(forPID pid: pid_t) -> String? { names[pid] }
    func bundleID(forPID pid: pid_t) -> String? { bundleIDs[pid] }
}

extension EventTapEntry {
    /// A rival that can take our keys unless position says otherwise: enabled,
    /// filtering, and asking for the same events we do.
    ///
    /// The last two parameters are the ways a neighbour is INNOCENT by the
    /// documented pipeline rather than by position — downstream of the session
    /// point, or scoped to one process — so a test that wants a real rival
    /// leaves them alone and a test about clearing someone sets one.
    static func contender(
        pid: pid_t,
        atHIDLocation: Bool = false,
        atAnnotatedSessionLocation: Bool = false,
        tapping: pid_t? = nil
    ) -> EventTapEntry {
        EventTapEntry(
            pid: pid,
            isEnabled: true,
            canConsume: true,
            mask: MediaKeyTranslation.systemDefinedMask,
            precedesSessionTaps: atHIDLocation,
            followsSessionTaps: atAnnotatedSessionLocation,
            processBeingTapped: tapping
        )
    }
}
