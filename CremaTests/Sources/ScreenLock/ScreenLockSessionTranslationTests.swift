import Foundation
import Testing
@testable import Crema

/// The session-dictionary decoding — the half of the lock source that used to be
/// unreachable from a test. Every test of the source injects a `sessionReader`,
/// so the production read and its defaults (what a missing key means, what an
/// unreadable session means) were policy nothing pinned: flipping either default
/// broke no test while changing whether the app suppresses the native OSD over a
/// lock shield.
///
/// The fixture values are `NSNumber(value: Bool)` because that IS the runtime
/// class the real dictionary carries (`__NSCFBoolean`, a bridged CFBoolean —
/// measured, not assumed). The keys are spelled out here instead of borrowing the
/// production constants on purpose: a test that reuses the constant cannot catch a
/// key that changed spelling, and the on-console literal doubles as the pin that
/// CGSession.h's public constant still resolves to this string.
struct ScreenLockSessionTranslationTests {

    private let onConsoleKey = "kCGSSessionOnConsoleKey"
    private let lockedKey = "CGSSessionScreenIsLocked"

    /// Reads the decoded pair through the policy that consumes it, so each case
    /// states the consequence (suppress or step aside), not just two booleans.
    private func isSafe(_ reading: (locked: Bool, onConsole: Bool)) -> Bool {
        ScreenLockReconciler.isSuppressionSafe(locked: reading.locked, onConsole: reading.onConsole)
    }

    /// The ordinary unlocked desktop: the lock key is ABSENT (it exists only while
    /// locked), so a missing key must read as unlocked. This is the default that
    /// looks like it should be cautious and must not be — reading absence as
    /// locked would suspend suppression for every user, forever, silently.
    @Test func anAbsentLockKeyIsTheNormalUnlockedSession() {
        let reading = ScreenLockSessionTranslation.decode([onConsoleKey: NSNumber(value: true)])
        #expect(!reading.locked)
        #expect(reading.onConsole)
        #expect(isSafe(reading))
    }

    /// The key appearing is the lock itself — the reading that has to reach the
    /// policy, or suppression stays engaged over a shield it cannot draw on.
    @Test func aPresentLockKeyReadsAsLocked() {
        let reading = ScreenLockSessionTranslation.decode([
            lockedKey: NSNumber(value: true),
            onConsoleKey: NSNumber(value: true),
        ])
        #expect(reading.locked)
        #expect(!isSafe(reading))
    }

    /// Fast-user-switch: unlocked but another session owns the screen, which is
    /// away for our purposes.
    @Test func offConsoleReadsAsAway() {
        let reading = ScreenLockSessionTranslation.decode([onConsoleKey: NSNumber(value: false)])
        #expect(!reading.onConsole)
        #expect(!isSafe(reading))
    }

    /// The risk decision, pinned: no dictionary means "cannot tell", and cannot
    /// tell means step aside. Suppression engaged on a session nobody can read is
    /// the one state that can leave the user with nothing — the native OSD
    /// swallowed and no HUD of ours over the lock shield; the other
    /// direction costs only our HUD (docs/DECISIONS.md:
    /// unreadable-session-is-unsafe).
    @Test func anUnreadableSessionReadsAsUnsafe() {
        #expect(!isSafe(ScreenLockSessionTranslation.decode(nil)))
    }

    /// Same direction for a dictionary that exists but cannot answer the
    /// on-console question — key gone, or a value of an unexpected type. That key
    /// is public API and always present in a live session, so its absence is an
    /// anomaly rather than a state, and an anomaly is not evidence the user is
    /// watching.
    @Test func aSessionThatCannotReportOnConsoleReadsAsUnsafe() {
        #expect(!isSafe(ScreenLockSessionTranslation.decode([:])))
        #expect(!isSafe(ScreenLockSessionTranslation.decode([onConsoleKey: "1"])))
    }
}
