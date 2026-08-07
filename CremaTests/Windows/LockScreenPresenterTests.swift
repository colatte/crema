import AppKit
import Testing
@testable import Crema

/// The presence rule as a table written independently of the `&&` chain it
/// checks — the rule's own expression would agree with any mutation of itself.
struct LockWidgetPresenceTests {

    @Test func allThreeAreRequired() {
        #expect(LockWidgetPresence.shouldPresent(enabled: true, locked: true, spaceAvailable: true))
    }

    @Test func theFeatureBeingOffOutranksEverything() {
        // Opt-in, born off. Nothing may put a window over a lock screen the user
        // never asked us to draw on.
        #expect(!LockWidgetPresence.shouldPresent(enabled: false, locked: true, spaceAvailable: true))
    }

    @Test func anUnlockedScreenGetsNothing() {
        #expect(!LockWidgetPresence.shouldPresent(enabled: true, locked: false, spaceAvailable: true))
    }

    @Test func withoutTheSpaceThereIsNoPointAndRealHarm() {
        // The window would render at the default level: invisible under the
        // shield, and sitting on the desktop the moment the user unlocks.
        #expect(!LockWidgetPresence.shouldPresent(enabled: true, locked: true, spaceAvailable: false))
    }

    private struct Row {
        let enabled: Bool
        let locked: Bool
        let space: Bool
        let present: Bool
    }

    @Test func theWholeTruthTable() {
        let rows = [
            Row(enabled: true, locked: true, space: true, present: true),
            Row(enabled: false, locked: true, space: true, present: false),
            Row(enabled: true, locked: false, space: true, present: false),
            Row(enabled: true, locked: true, space: false, present: false),
            Row(enabled: false, locked: false, space: true, present: false),
            Row(enabled: false, locked: true, space: false, present: false),
            Row(enabled: true, locked: false, space: false, present: false),
            Row(enabled: false, locked: false, space: false, present: false),
        ]
        #expect(rows.count == 8)   // every combination, none skipped
        for row in rows {
            #expect(
                LockWidgetPresence.shouldPresent(
                    enabled: row.enabled, locked: row.locked, spaceAvailable: row.space
                ) == row.present,
                "enabled=\(row.enabled) locked=\(row.locked) space=\(row.space)"
            )
        }
    }
}

/// The mirror's guarded write. Not ceremony: the source polls on a 30 s tail
/// forever, and an unchanged write to an `@Observable` property still rebuilds
/// every view reading it.
@MainActor
struct LockScreenMirrorTests {

    @Test func itStartsUnlocked() {
        // The conservative default is the one that draws nothing. A mirror born
        // locked would flash the surface at launch on every machine.
        #expect(!LockScreenMirror().isLocked)
    }

    @Test func itCarriesTransitionsBothWays() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        #expect(mirror.isLocked)
        mirror.report(locked: false)
        #expect(!mirror.isLocked)
    }
}

/// The presenter's lifecycle, over a counting panel factory and a recording
/// space. No real WindowServer — the space is a double — but real NSPanels: the
/// factory builds them so the panel's own constructor decisions are exercised
/// too, and every test closes what it opened.
@MainActor
struct LockScreenPresenterLifecycleTests {

    /// Counts what the presenter asked for, and can refuse on demand.
    ///
    /// It does build a real `LockScreenPanel` — and therefore a real
    /// screen-sized NSPanel, ordered front — because the space it is handed is a
    /// `RecordingRaisedSpace` that reports available, so the factory's `guard`
    /// falls through. That is deliberate: the panel's own constructor decisions
    /// (born click-through, adopted exactly once) are worth exercising here. What
    /// the spy buys is the COUNT and the refusal, neither of which the real
    /// factory can report.
    @MainActor
    final class FactorySpy {
        private(set) var builds = 0
        var refuses = false

        func make(
            _ screen: NSScreen,
            _ coordinator: Coordinator,
            _ space: any RaisedSpace,
            _ lowPower: LowPowerModeMirror,
            _ artwork: LockArtworkResolver
        ) -> LockScreenPanel? {
            builds += 1
            guard !refuses else { return nil }
            return LockScreenPanel(
                screen: screen, coordinator: coordinator, space: space,
                lowPower: lowPower, artwork: artwork
            )
        }
    }

    private func makePresenter(
        enabled: Bool,
        mirror: LockScreenMirror,
        spy: FactorySpy,
        space: RecordingRaisedSpace = RecordingRaisedSpace()
    ) -> (LockScreenPresenter, CoordinatorHarness) {
        let harness = CoordinatorHarness()
        let presenter = LockScreenPresenter(
            coordinator: harness.coordinator,
            lock: mirror,
            space: space,
            lowPower: LowPowerModeMirror(),
            artwork: LockArtworkResolver(lookup: MockArtworkLookup(), enabled: false),
            enabled: enabled,
            makePanel: spy.make
        )
        return (presenter, harness)
    }

    @Test func anUnlockedStartBuildsNothing() {
        let mirror = LockScreenMirror()
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        // No window at all during ordinary use: the surface is born on the lock,
        // not kept hidden behind it.
        #expect(spy.builds == 0)
    }

    @Test func startingAlreadyLockedBuildsImmediately() {
        // Launching (or enabling) while the screen is already locked is a real
        // path — a relaunch after a crash, or the login item on a locked Mac.
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 1)
    }

    @Test func theFeatureBeingOffBuildsNothingEvenLocked() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: false, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 0)
    }

    @Test func enablingWhileLockedBuildsWithoutWaitingForTheNextLock() {
        // The Settings toggle has to take effect now. Waiting for the next lock
        // cycle is the class of bug the "every control owes an onChange into the
        // core" rule exists to prevent.
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: false, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 0)

        presenter.setEnabled(true)
        #expect(spy.builds == 1)
    }

    @Test func disablingWhileLockedTakesTheSurfaceDownAtOnce() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 1)

        presenter.setEnabled(false)
        // Turning it off with the surface up must remove it, not leave it until
        // the next unlock.
        presenter.setEnabled(true)
        #expect(spy.builds == 2, "a second build proves the first surface was actually torn down")
    }

    @Test func anUnavailableSpaceNeverBuilds() {
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        let (presenter, _) = makePresenter(
            enabled: true, mirror: mirror, spy: spy, space: RecordingRaisedSpace(isAvailable: false)
        )
        presenter.start()
        // The presence rule refuses before the factory is ever asked — the panel
        // has its own guard, but paying for a window to throw it away is waste.
        #expect(spy.builds == 0)
    }

    @Test func aBuildThatFailedIsRetriedOnAWakeEdgeRatherThanLostForTheLock() async {
        // The real shape of this: the lock edge lands while the displays are
        // asleep or mid-reconfiguration, no screen answers, and the surface used
        // to be gone for the WHOLE lock — every later edge acted on an existing
        // panel, and the lock bit was already true so nothing re-entered the
        // decision. Here the refusal stands in for that missing screen.
        let mirror = LockScreenMirror()
        mirror.report(locked: true)
        let spy = FactorySpy()
        spy.refuses = true
        let (presenter, _) = makePresenter(enabled: true, mirror: mirror, spy: spy)
        presenter.start()
        #expect(spy.builds == 1)

        spy.refuses = false
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        // The observer is queued on .main, so the edge lands on a later turn.
        #expect(await eventually { spy.builds == 2 })

        // And it is convergent: a second edge with a surface already up must not
        // build another one on top of it. Proven by a sentinel posted BEHIND it
        // on the same ordered queue rather than by waiting — a wait can only
        // ever show that the test was patient, and a wait long enough to mean
        // something is a wait long enough to hurt.
        let barrier = EdgeBarrier()
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.screensDidWakeNotification, object: nil
        )
        barrier.arm()
        #expect(await eventually { barrier.passed })
        #expect(spy.builds == 2)

        presenter.setEnabled(false)
    }
}

/// A notification posted behind another on `NSWorkspace`'s centre, both queued
/// on `.main` and therefore delivered in post order. When this one has landed,
/// whatever was posted before it has already been handled — which is how a
/// "nothing happened" assertion gets a positive signal instead of a deadline.
@MainActor
final class EdgeBarrier {
    private static let name = Notification.Name("crema.test.lockPresenterBarrier")
    /// Read only in `deinit`, after every other access has ended — the same
    /// lifecycle bracket the app's own observer arrays document.
    private nonisolated(unsafe) var token: NSObjectProtocol?
    private(set) var passed = false

    func arm() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: Self.name, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.passed = true }
        }
        NSWorkspace.shared.notificationCenter.post(name: Self.name, object: nil)
    }

    deinit {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
