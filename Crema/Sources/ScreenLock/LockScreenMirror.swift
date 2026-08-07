import Observation

/// Whether the screen is locked, for readers that need that fact on its own.
///
/// A second reader cannot simply take `ScreenLockSource.updates`: it is a
/// single-consumer `AsyncStream` already iterated by `SuppressionLockController`,
/// and a second `for await` would split the values between the two — silently,
/// each seeing roughly half the transitions. The same hazard AppCore already
/// names for `mediaKeys.updates`. So the source reports here as well, and every
/// other reader observes this instead.
///
/// It carries `locked`, NOT `isSuppressionSafe`, and the two are not the same
/// question. Safe collapses "locked" and "off-console" into one bit because
/// suppression must step aside for both. The lock surface must not: drawing a
/// now-playing card because someone fast-user-switched to another account would
/// put this user's listening on a stranger's screen.
///
/// The write is guarded for the reason every mirror here is — an unchanged write
/// to an `@Observable` property still rebuilds every view reading it, and the
/// source polls on a 30 s tail forever.
@Observable
@MainActor
final class LockScreenMirror {
    private(set) var isLocked = false

    func report(locked: Bool) {
        if locked != isLocked { isLocked = locked }
    }
}
