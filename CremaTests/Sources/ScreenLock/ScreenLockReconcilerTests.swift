import Testing
@testable import Crema

/// The pure reconciliation above the system border: authoritative poll →
/// suppression-safe state, deduplicated. Edges are only triggers; these tests
/// pin the poll-to-state mapping and the transition dedup directly.
struct ScreenLockReconcilerTests {

    @Test func safeOnlyWhenUnlockedAndOnConsole() {
        #expect(ScreenLockReconciler.isSuppressionSafe(locked: false, onConsole: true))
        #expect(!ScreenLockReconciler.isSuppressionSafe(locked: true, onConsole: true))
        // Off-console (fast-user-switch) is unsafe even while unlocked.
        #expect(!ScreenLockReconciler.isSuppressionSafe(locked: false, onConsole: false))
        #expect(!ScreenLockReconciler.isSuppressionSafe(locked: true, onConsole: false))
    }

    @Test func initialStateReflectsTheOpeningPoll() {
        #expect(ScreenLockReconciler(locked: false, onConsole: true).lastSafe)
        #expect(!ScreenLockReconciler(locked: true, onConsole: true).lastSafe)
    }

    @Test func lockThenUnlockEmitsEachRealTransition() {
        var reconciler = ScreenLockReconciler(locked: false, onConsole: true)
        #expect(reconciler.reconcile(locked: true, onConsole: true) == false)
        #expect(reconciler.reconcile(locked: false, onConsole: true) == true)
    }

    @Test func aConfirmingPollDoesNotFlip() {
        // An edge that re-reads the same truth (a redundant screenIsLocked, or a
        // poll confirming no change) must be silent — no spurious re-engage.
        var reconciler = ScreenLockReconciler(locked: false, onConsole: true)
        #expect(reconciler.reconcile(locked: false, onConsole: true) == nil)
        #expect(reconciler.reconcile(locked: true, onConsole: true) == false)
        #expect(reconciler.reconcile(locked: true, onConsole: true) == nil)
    }

    @Test func offConsoleTransitionsLikeALock() {
        var reconciler = ScreenLockReconciler(locked: false, onConsole: true)
        #expect(reconciler.reconcile(locked: false, onConsole: false) == false)
        #expect(reconciler.reconcile(locked: false, onConsole: true) == true)
    }

    @Test func launchedWhileLockedStartsUnsafeAndReturnEmits() {
        var reconciler = ScreenLockReconciler(locked: true, onConsole: true)
        #expect(!reconciler.lastSafe)
        // A confirming lock poll stays silent; only the unlock emits.
        #expect(reconciler.reconcile(locked: true, onConsole: true) == nil)
        #expect(reconciler.reconcile(locked: false, onConsole: true) == true)
    }
}
