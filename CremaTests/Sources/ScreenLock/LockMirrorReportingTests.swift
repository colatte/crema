import Testing
@testable import Crema

/// Where the lock mirror is written, driven through the REAL source over an
/// injected session reader — no CoreGraphics, no notifications.
///
/// The mirror is reported BEFORE `ScreenLockReconciler.reconcile`, and this file
/// exists because that ordering is the entire correctness of a second reader.
///
/// The reconciler deduplicates on `isSuppressionSafe`, which is
/// `!locked && onConsole`. Off the console, both a lock and an unlock leave that
/// expression false, so `reconcile` returns nil and `reconcileFromPoll` takes its
/// early return. A mirror written after the guard would sit at whatever it last
/// saw while the screen locked and unlocked in front of it — and the lock
/// surface would either never appear or never leave.
///
/// Moving `lockMirror?.report` below the guard is the mutation these tests exist
/// to kill; every other assertion in the suite stays green under it.
@MainActor
struct LockMirrorReportingTests {

    /// Mutable session state the injected reader reflects, the same shape the
    /// settle-re-read tests use.
    @MainActor
    final class SessionBox {
        var locked: Bool
        var onConsole: Bool
        init(locked: Bool, onConsole: Bool) {
            self.locked = locked
            self.onConsole = onConsole
        }
    }

    private func makeSource(
        _ box: SessionBox,
        mirror: LockScreenMirror
    ) -> DistributedNotificationScreenLockSource {
        DistributedNotificationScreenLockSource(
            clock: TestSleepClock(),
            sessionReader: { (locked: box.locked, onConsole: box.onConsole) },
            lockMirror: mirror
        )
    }

    @Test func theMirrorIsSeededByTheAuthoritativeReadAtLaunch() {
        // Launching on a locked Mac must not need an edge to learn it. The same
        // reason `isSuppressionSafe` is readable synchronously.
        let mirror = LockScreenMirror()
        _ = makeSource(SessionBox(locked: true, onConsole: true), mirror: mirror)
        #expect(mirror.isLocked)
    }

    @Test func anOrdinaryLockAndUnlockMovesTheMirror() {
        let box = SessionBox(locked: false, onConsole: true)
        let mirror = LockScreenMirror()
        let source = makeSource(box, mirror: mirror)
        #expect(!mirror.isLocked)

        box.locked = true
        source.handleEdge()
        #expect(mirror.isLocked)

        box.locked = false
        source.handleEdge()
        #expect(!mirror.isLocked)
    }

    /// The case the ordering exists for.
    ///
    /// Off the console, `safe` is false whether the screen is locked or not, so
    /// the reconciler deduplicates both transitions away and the poll returns
    /// early. The mirror must still have seen them.
    @Test func theMirrorSeesTransitionsTheReconcilerDeduplicatesAway() {
        let box = SessionBox(locked: false, onConsole: false)
        let mirror = LockScreenMirror()
        let source = makeSource(box, mirror: mirror)

        // Both readings decode to "not safe to suppress", so nothing reaches the
        // stream from here on — proving the mirror is not fed by it.
        #expect(!source.isSuppressionSafe)

        box.locked = true
        source.handleEdge()
        #expect(mirror.isLocked, "the mirror must be written before the reconciler's dedup")
        #expect(!source.isSuppressionSafe, "safe was false before and stays false — nothing was emitted")

        box.locked = false
        source.handleEdge()
        #expect(!mirror.isLocked, "and back again, still with no change in safe")
        #expect(!source.isSuppressionSafe)
    }

    @Test func aMirrorlessSourceStillWorks() {
        // Nobody is obliged to pass one: the suppression path never needs the
        // raw bit, and the parameter defaults to nil so no existing call site
        // had to change.
        let box = SessionBox(locked: false, onConsole: true)
        let source = DistributedNotificationScreenLockSource(
            clock: TestSleepClock(),
            sessionReader: { (locked: box.locked, onConsole: box.onConsole) }
        )
        #expect(source.isSuppressionSafe)
        box.locked = true
        source.handleEdge()
        #expect(!source.isSuppressionSafe)
    }
}
