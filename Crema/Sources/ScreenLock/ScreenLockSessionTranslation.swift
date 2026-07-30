import CoreGraphics
import Foundation

/// Pure decoding of the window-server session dictionary into the two facts the
/// lock policy needs. Above the border for the same reason `ScreenLockReconciler`
/// is: `CGSessionCopyCurrentDictionary` is the one call a unit test cannot make,
/// so everything decided ABOUT its result — which key means what, which value
/// types arrive, what an absent key means — belongs here, where a test pins it.
///
/// The two keys have different pedigrees, and treating them alike hid the one
/// that is genuinely private:
///
/// - `kCGSSessionOnConsoleKey` is PUBLIC: CGSession.h declares
///   `kCGSessionOnConsoleKey` as exactly this string — used here as the constant,
///   so the compiler owns the spelling — and documents the value as a
///   **CFBoolean** (measured: `__NSCFBoolean`, hence the NSNumber cast). It is
///   read at all because on-console excludes fast-user-switch, where another
///   session owns the screen.
/// - `CGSSessionScreenIsLocked` is declared by no SDK header — the undocumented
///   one, stable for years and fine outside the Mac App Store. Measured (macOS 26,
///   Apple Silicon, live Aqua session) it is **absent while unlocked** and appears
///   only once the screen locks, so an absent key means UNLOCKED: the normal
///   state, not an anomaly. It is therefore the one default here that must never
///   be flipped to the cautious side — reading absence as locked would suspend
///   suppression forever and kill the feature in silence.
///
/// Anything unreadable — no dictionary at all, or a session that cannot report
/// on-console — is "cannot tell", and cannot tell decodes as NOT safe, so
/// suppression steps aside. Being wrong is asymmetric: engaged over a lock shield
/// the user gets no feedback at all (native OSD swallowed, our own HUD impossible
/// there — the NO-GO the lock-aware policy exists to prevent), while disengaged on
/// a healthy session costs only our own HUD. Holding the last reading instead was
/// rejected: launch has no last reading, so the same choice would still have to be
/// made, with one more path to get wrong.
/// (docs/DECISIONS.md: unreadable-session-is-unsafe)
enum ScreenLockSessionTranslation {
    private static let sessionScreenIsLockedKey = "CGSSessionScreenIsLocked"
    private static let sessionOnConsoleKey = kCGSessionOnConsoleKey as String

    /// The absences deliberately point opposite ways — no lock key is the normal
    /// unlocked desktop, no on-console key is a session that cannot answer.
    static func decode(_ dictionary: [String: Any]?) -> (locked: Bool, onConsole: Bool) {
        guard let dictionary else { return (locked: true, onConsole: false) }
        return (
            locked: (dictionary[sessionScreenIsLockedKey] as? NSNumber)?.boolValue ?? false,
            onConsole: (dictionary[sessionOnConsoleKey] as? NSNumber)?.boolValue ?? false
        )
    }
}
